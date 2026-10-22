--TEST--
CVE-2026-109618: exhausting memory_limit ends the process without running shutdown code
--INI--
memory_limit=8M
display_errors=1
html_errors=0
--FILE--
<?php
register_shutdown_function(function () { echo "shutdown function ran\n"; });
class D { function __destruct() { echo "destructor ran\n"; } }
$d = new D;
$s = str_repeat("x", 32 * 1024 * 1024);
echo "not reached\n";
?>
--EXPECTF--
%AFatal error: Allowed memory size of %d bytes exhausted%s(tried to allocate %d bytes)%s
