--TEST--
CVE-2026-109618: unused and duplicate multipart part headers are ignored
--INI--
file_uploads=1
display_errors=1
html_errors=0
--POST_RAW--
Content-Type: multipart/form-data; boundary=bnd123
--bnd123
X-Junk: aaaaaaaaaaaaaaaa
Content-Disposition: form-data; name="first"
Content-Disposition: form-data; name="second"
X-More-Junk: bbbbbbbbbbbbbbbb
  folded continuation of the junk header

value
--bnd123
Content-Disposition: form-data; name="upload"; filename="a.txt"
Content-Type: text/plain
Content-Type: application/x-not-this-one

file contents
--bnd123--
--FILE--
<?php
var_dump($_POST);
var_dump($_FILES['upload']['name'], $_FILES['upload']['type'], $_FILES['upload']['size']);
?>
--EXPECT--
array(1) {
  ["first"]=>
  string(5) "value"
}
string(5) "a.txt"
string(10) "text/plain"
int(13)
