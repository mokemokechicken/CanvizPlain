What is CanvizPlain?
====================

CanvizPlain is

* porting of [Canviz 0.1](https://code.google.com/p/canviz/)
* written by CoffeeScript and not using prototype.js

Difference from original Canviz
==============================

* no 'load_graph()' method in Canviz.
* Maybe some new bugs...

How To Use
==========

```javascript:sample
// include canviz.js

var xdotText = "... Your xdot text ...";
var canviz = new Canviz("canvas");  // ID of a div like tag.
canviz.parse(xdotText);
```

Please see example/index.html

License
=======

MIT License: http://mokemokechicken.mit-license.org/
