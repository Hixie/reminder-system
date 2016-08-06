{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit network;

interface

{$DEFINE VERBOSE}

uses
   corenetwork, corewebsocket;

type
   IClient = interface
      procedure Pong();
      procedure WriteFrame(const Message: UTF8String);
   end;

   TUIConnectedCallback = procedure (const Client: IClient);
   TMessageCallback = procedure (const S: UTF8String; const Client: IClient);

   TServer = class(TNetworkServer)
    protected
      FMessageCallback: TMessageCallback;
      FUIConnectedCallback: TUIConnectedCallback;
      FWebSocketListener, FTCPListener: TListenerSocket;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
    public
      constructor Create(const WebSocketPort, TCPPort: Word; const MessageCallback: TMessageCallback; const UIConnectedCallback: TUIConnectedCallback);
      procedure BroadcastUI(Message: UTF8String);
      procedure BroadcastNotification(Message: UTF8String);
   end;

implementation

type
   TWebSocketClient = class(TWebSocket, IClient)
    protected
      FMessageCallback: TMessageCallback; // set directly by TServer
      FUIConnectedCallback: TUIConnectedCallback; // set directly by TServer
      procedure HandleMessage(Message: UTF8String); override;
      procedure Handshake(); override;
    public
      procedure Pong();
   end;

   TTCPClient = class(TNetworkSocket, IClient)
    protected
      FMessageCallback: TMessageCallback; // set directly by TServer
      FUIConnectedCallback: TUIConnectedCallback; // set directly by TServer
      FBuffer: UTF8String;
      FWantUI: Boolean;
      function InternalRead(Data: array of byte): Boolean; override;
    public
      procedure WriteFrame(const Message: UTF8String);
      procedure Pong();
      property WantUI: Boolean read FWantUI;
   end;

      
procedure TWebSocketClient.HandleMessage(Message: UTF8String);
begin
   Assert(Assigned(FMessageCallback));
   FMessageCallback(Message, Self);
end;

procedure TWebSocketClient.Handshake();
begin
   inherited;
   Assert(Assigned(FUIConnectedCallback));
   FUIConnectedCallback(Self);
end;

procedure TWebSocketClient.Pong();
begin
   WriteFrame('pong');
end;


function TTCPClient.InternalRead(Data: array of byte): Boolean;
var
   Index: Cardinal;
begin
   Assert(Length(Data) > 0);
   for Index := Low(Data) to High(Data) do // $R-
   begin
      FBuffer := FBuffer + Chr(Data[Index]);
      if ((Length(FBuffer) >= 3) and (FBuffer[Length(FBuffer)-2] = #0)
                                 and (FBuffer[Length(FBuffer)-1] = #0)
                                 and (FBuffer[Length(FBuffer)] = #0)) then
      begin
         SetLength(FBuffer, Length(FBuffer)-3);
         if (FBuffer = '') then
         begin
            Pong();
         end
         else
         if (FBuffer = 'enable-ui') then
         begin
            if (FWantUI) then
            begin
               Result := False;
               exit;
            end;
            FWantUI := True;
            Assert(Assigned(FUIConnectedCallback));
            FUIConnectedCallback(Self);
         end
         else
         begin
            Assert(Assigned(FMessageCallback));
            // XXX check FBuffer is valid UTF8
            FMessageCallback(FBuffer, Self);
         end;
         FBuffer := '';
      end;
      if (Length(FBuffer) > 1024) then
      begin
         {$IFDEF DEBUG} Writeln('<overloaded buffer - disconnecting>'); {$ENDIF}
         Result := False;
         exit;
      end;
   end;
   Result := True;
end;

procedure TTCPClient.WriteFrame(const Message: UTF8String);
begin
   // XXX check FBuffer is valid UTF8
   Assert(Pos(#0#0#0, Message) = 0);
   Write(Message + #0#0#0);
end;

procedure TTCPClient.Pong();
begin
   Write(#0#0#0);
end;

      
constructor TServer.Create(const WebSocketPort, TCPPort: Word; const MessageCallback: TMessageCallback; const UIConnectedCallback: TUIConnectedCallback);
begin
   inherited Create();
   FMessageCallback := MessageCallback;
   FUIConnectedCallback := UIConnectedCallback;
   FWebSocketListener := AddListener(WebSocketPort);
   FTCPListener := AddListener(TCPPort);
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   if (AListenerSocket = FWebSocketListener) then
   begin
      Result := TWebSocketClient.Create(AListenerSocket);
      (Result as TWebSocketClient).FMessageCallback := FMessageCallback;
      (Result as TWebSocketClient).FUIConnectedCallback := FUIConnectedCallback;
   end
   else
   if (AListenerSocket = FTCPListener) then
   begin
      Result := TTCPClient.Create(AListenerSocket);
      (Result as TTCPClient).FMessageCallback := FMessageCallback;
      (Result as TTCPClient).FUIConnectedCallback := FUIConnectedCallback;
   end
   else
   begin
      Assert(False);
      Result := nil;
   end;
end;

procedure TServer.BroadcastUI(Message: UTF8String);
var
   Item: PSocketListItem;
begin
   // XXX check Message is valid UTF8
   Item := FList;
   while (Assigned(Item)) do
   begin
      Assert(Assigned(Item^.Value));
      if (Item^.Value is TTCPClient) then
      begin
         if ((Item^.Value as TTCPClient).WantUI) then
            (Item^.Value as TTCPClient).WriteFrame(Message);
      end
      else
      if (Item^.Value is TWebSocketClient) then
      begin
         if ((Item^.Value as TWebSocketClient).Ready) then
            (Item^.Value as TWebSocketClient).WriteFrame(Message);
      end;
      Item := Item^.Next;
   end;
end;

procedure TServer.BroadcastNotification(Message: UTF8String);
var
   Item: PSocketListItem;
begin
   // XXX check Message is valid UTF8
   Item := FList;
   while (Assigned(Item)) do
   begin
      Assert(Assigned(Item^.Value));
      if (Item^.Value is TTCPClient) then
         (Item^.Value as TTCPClient).WriteFrame(Message);
      Item := Item^.Next;
   end;
end;

end.
