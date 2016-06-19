/*

Based on http://ejohn.org/blog/simple-javascript-inheritance/

Copyright (c) <year> <copyright holders>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

(function(){
  var extending = false;
  var fnTest = /xyz/.test(function(){xyz;}) ? /\binherited\b/ : /.*/;

  // The base Class implementation (does nothing)
  this.Class = function () { };

  // Create a new Class that inherits from this class
  this.Class.extend = function(template) {
    var parentPrototype = this.prototype;

    // Instantiate a base class (but only create the instance,
    // don't run the init constructor)
    extending = true;
    var subclassPrototype = new this();
    extending = false;

    // Copy the properties over onto the new prototype
    for (var name in template) {
      // Check if we're overwriting an existing function
      subclassPrototype[name] = typeof template[name] == "function" &&
                                fnTest.test(template[name]) ? // only do the hard work if the function references inherited()
        (function(name, fn){
          return function() {
            // Temporarily add a new .inherited() method that is the same method but on the superclass
            var tmp = this.inherited;
            this.inherited = parentPrototype[name];
            var ret;
            try {
                ret = fn.apply(this, arguments);
            } finally {
                this.inherited = tmp;
            }
            return ret;
          };
        })(name, template[name]) : template[name];
    }

    var Subclass = function () {
      if (!extending && this.init)
        this.init.apply(this, arguments);
    }
    Subclass.prototype = subclassPrototype;
    Subclass.prototype.constructor = Subclass;

    Subclass.extend = arguments.callee;

    // special feature for ISD serialisation/deserialisation mechanism
    Subclass.restore = function () {
      extending = true;
      var obj = new Subclass();
      extending = false;
      obj.restore.apply(obj, arguments);
      return obj;
    };

    return Subclass;
  };
})();
