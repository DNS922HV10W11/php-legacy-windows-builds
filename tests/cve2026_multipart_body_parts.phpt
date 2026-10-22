--TEST--
max_multipart_body_parts limits the number of multipart parts (CVE-2023-0662)
--INI--
max_multipart_body_parts=3
display_errors=1
html_errors=0
--POST_RAW--
Content-Type: multipart/form-data; boundary=bnd123
--bnd123
Content-Disposition: form-data; name="a"

1
--bnd123
Content-Disposition: form-data; name="b"

2
--bnd123
Content-Disposition: form-data; name="c"

3
--bnd123
Content-Disposition: form-data; name="d"

4
--bnd123
Content-Disposition: form-data; name="e"

5
--bnd123--
--FILE--
<?php
var_dump(array_keys($_POST));
?>
--EXPECTF--
%AMultipart body parts limit exceeded 3. To increase the limit change max_multipart_body_parts in php.ini.%A
array(3) {
  [0]=>
  string(1) "a"
  [1]=>
  string(1) "b"
  [2]=>
  string(1) "c"
}
