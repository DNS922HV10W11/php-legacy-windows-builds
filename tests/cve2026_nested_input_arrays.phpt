--TEST--
CVE-2026-109618: nested request arrays start small and still grow correctly
--INI--
max_input_nesting_level=64
--GET--
a[]=1&a[]=2&a[]=3&a[x][y][z]=4&b[k1]=v1&b[k2]=v2&b[k3]=v3&b[k4]=v4&b[k5]=v5&b[k6]=v6&b[k7]=v7&b[k8]=v8&b[k9]=v9&b[k10]=v10&c[][][]=deep&c[][][]=deeper&d=plain&e[0]=zero&e[1]=one&e[x]=ex
--POST--
p[]=1&p[]=2&p[]=3&p[]=4&p[]=5&p[]=6&p[]=7&p[]=8&p[]=9&p[]=10&p[]=11&p[]=12&p[]=13&p[]=14&p[]=15&p[]=16&p[]=17&q[a][b]=c&q[a][d]=e&q[f]=g
--COOKIE--
ck[x]=1; ck[y]=2; ck[z]=3; plain=4
--FILE--
<?php
function p($v, $i = '') {
	foreach ($v as $k => $x) {
		if (is_array($x)) {
			echo "$i$k (", count($x), "):\n";
			p($x, "$i  ");
		} else {
			echo "$i$k = $x\n";
		}
	}
}
echo "GET\n"; p($_GET);
echo "POST\n"; p($_POST);
echo "COOKIE\n"; p($_COOKIE);

$_GET['a'][] = 'appended';
$_GET['b']['new'] = 'x';
unset($_GET['b']['k5']);
$copy = $_POST['p'];
$copy[] = 18;
echo count($_GET['a']), ' ', count($_GET['b']), ' ', isset($_GET['b']['k5']) ? 'set' : 'unset', ' ', $_GET['b']['k10'], "\n";
echo count($copy), ' ', count($_POST['p']), ' ', $copy[17], ' ', $_POST['p'][16], "\n";
?>
--EXPECT--
GET
a (4):
  0 = 1
  1 = 2
  2 = 3
  x (1):
    y (1):
      z = 4
b (10):
  k1 = v1
  k2 = v2
  k3 = v3
  k4 = v4
  k5 = v5
  k6 = v6
  k7 = v7
  k8 = v8
  k9 = v9
  k10 = v10
c (2):
  0 (1):
    0 (1):
      0 = deep
  1 (1):
    0 (1):
      0 = deeper
d = plain
e (3):
  0 = zero
  1 = one
  x = ex
POST
p (17):
  0 = 1
  1 = 2
  2 = 3
  3 = 4
  4 = 5
  5 = 6
  6 = 7
  7 = 8
  8 = 9
  9 = 10
  10 = 11
  11 = 12
  12 = 13
  13 = 14
  14 = 15
  15 = 16
  16 = 17
q (2):
  a (2):
    b = c
    d = e
  f = g
COOKIE
ck (3):
  x = 1
  y = 2
  z = 3
plain = 4
5 10 unset v10
18 17 18 17
