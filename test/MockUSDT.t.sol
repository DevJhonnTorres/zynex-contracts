// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MockUSDT.sol";

contract MockUSDTTest is Test {
    MockUSDT usdt;
    address alice = makeAddr("alice");

    function setUp() public {
        usdt = new MockUSDT();
    }

    function test_nombre_y_simbolo() public view {
        assertEq(usdt.name(), "Mock USDT");
        assertEq(usdt.symbol(), "USDT");
    }

    function test_decimales_son_6() public view {
        assertEq(usdt.decimals(), 6);
    }

    function test_mint_acredita_balance() public {
        usdt.mint(alice, 1000e6);
        assertEq(usdt.balanceOf(alice), 1000e6);
    }

    function test_mint_cualquiera_puede() public {
        vm.prank(alice);
        usdt.mint(alice, 500e6);
        assertEq(usdt.balanceOf(alice), 500e6);
    }
}
