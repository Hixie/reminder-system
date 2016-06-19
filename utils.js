
function assert(condition) {
  if (!condition) {
    console.error('assertion failed');
    console.trace();
    //var keepGoing = 0;
    debugger;
    //if (!keepGoing)
    //  throw new Error(message);
  }
}

function F( /* varargs... */) {
  var fragment = document.createDocumentFragment();
  for (var index = 0; index < arguments.length; index += 1) {
    if (arguments[index] instanceof Array) {
      fragment.appendChild(F.apply(this, arguments[index]));
    } else if (typeof arguments[index] == 'string') {
      fragment.appendChild(document.createTextNode(arguments[index]));
    } else {
      assert(arguments[index] instanceof Node);
      fragment.appendChild(arguments[index]);
    }
  }
  return fragment;
}

function E(name, /* optional */ attributes /*, varargs... */) {
  var element = document.createElement(name);
  var index = 1;
  if ((arguments.length > 1) && (typeof attributes != 'string') &&
      (!(attributes instanceof Node)) && (!(attributes instanceof Array))) {
    for (var attName in attributes) {
      if (typeof attributes[attName] == 'boolean') {
        if (attributes[attName])
          element.setAttribute(attName, '');
      } else if (typeof attributes[attName] == 'function') {
        element[attName] = attributes[attName];
      } else {
        element.setAttribute(attName, attributes[attName]);
      }
    }
    index = 2;
  }
  for (; index < arguments.length; index += 1) {
    if (arguments[index] instanceof Array) {
      element.appendChild(F.apply(this, arguments[index]));
    } else if (typeof arguments[index] == 'string') {
      element.appendChild(document.createTextNode(arguments[index]));
    } else {
      assert(arguments[index] instanceof Node);
      element.appendChild(arguments[index]);
    }
  }
  return element;
}

function replaceChildren(parent, children) { // don't forget children is an **array**!
  parent.textContent = '';
  for (var index = 0; index < children.length; index += 1)
    parent.appendChild(children[index]);
}
