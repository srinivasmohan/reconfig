v0.0.2
======
* Added `pattern` to config JSON - This allows use of alternate embedded pattern e.g. `#% %#` instead of standard `<% %>`
* Swapped to use Erubis instead of Erb for this to happen.
* Supports fetching alternate keys too (via `altkeys`)
* Template context variable is now `@reconfig` (Hash)

v0.0.1
======

* Initial release - Sep 15 2014, Srinivas.
