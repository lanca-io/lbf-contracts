// SPDX-License-Identifier: UNLICENSED
/* solhint-disable func-name-mixedcase */
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IOUToken} from "contracts/Rebalancer/IOUToken.sol";
import {LPToken} from "contracts/ParentPool/LPToken.sol";

contract TokensTest is Test {
    IOUToken public iouToken;
    LPToken public lpToken;

    address public admin;
    address public minter;
    address public user1;
    address public user2;
    address public unauthorized;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        unauthorized = makeAddr("unauthorized");

        iouToken = new IOUToken(admin, minter, 6);
        lpToken = new LPToken(admin, minter, 6);
    }

    /* -- IOUToken Tests -- */

    function test_IOUToken_Constructor() public view {
        assertEq(iouToken.name(), "LancaIOU-USDC");
        assertEq(iouToken.symbol(), "LIOU-USDC");
        assertEq(iouToken.decimals(), 6);

        assertTrue(iouToken.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(iouToken.hasRole(MINTER_ROLE, minter));
    }

    function test_IOUToken_Mint_Success() public {
        uint256 mintAmount = 100e6;

        vm.prank(minter);
        iouToken.mint(user1, mintAmount);

        assertEq(iouToken.balanceOf(user1), mintAmount);
    }

    function test_IOUToken_Mint_RevertsUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                MINTER_ROLE
            )
        );

        vm.prank(unauthorized);
        iouToken.mint(user1, 0);
    }

    function test_IOUToken_Burn_Success() public {
        vm.prank(minter);
        iouToken.mint(user1, 200e6);

        vm.prank(minter);
        iouToken.burn(user1, 100e6);

        assertEq(iouToken.balanceOf(user1), 100e6);
    }

    function test_IOUToken_Burn_RevertsUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                MINTER_ROLE
            )
        );

        vm.prank(unauthorized);
        iouToken.burn(user1, 0);
    }

    /* -- LPToken Tests -- */

    function test_LPToken_Constructor() public view {
        assertEq(lpToken.name(), "ConceroLP-USDC");
        assertEq(lpToken.symbol(), "CLP-USDC");
        assertEq(lpToken.decimals(), 6);

        assertTrue(lpToken.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(lpToken.hasRole(MINTER_ROLE, minter));
    }

    function test_LPToken_Mint_Success() public {
        uint256 mintAmount = 100e6;

        vm.prank(minter);
        lpToken.mint(user1, mintAmount);

        assertEq(lpToken.balanceOf(user1), mintAmount);
    }

    function test_LPToken_Mint_RevertsUnauthorized() public {
        uint256 mintAmount = 100e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user1,
                MINTER_ROLE
            )
        );

        vm.prank(user1);
        lpToken.mint(user1, mintAmount);
    }

    function test_LPToken_Burn_Success() public {
        uint256 mintAmount = 200e6;
        uint256 burnAmount = 100e6;

        vm.prank(minter);
        lpToken.mint(user1, mintAmount);

        vm.prank(user1);
        lpToken.burn(burnAmount);

        assertEq(lpToken.balanceOf(user1), mintAmount - burnAmount);
    }

    function test_LPToken_BurnFrom_Success() public {
        uint256 mintAmount = 200e6;
        uint256 burnAmount = 100e6;

        vm.prank(minter);
        lpToken.mint(user1, mintAmount);

        vm.prank(user1);
        lpToken.approve(user2, burnAmount);

        vm.prank(user2);
        lpToken.burnFrom(user1, burnAmount);

        assertEq(lpToken.balanceOf(user1), mintAmount - burnAmount);
        assertEq(lpToken.allowance(user1, user2), 0);
    }
}
