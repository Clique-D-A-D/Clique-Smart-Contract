// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/RentalPlatform.sol";

contract RentalPlatformTest is Test {

    RentalPlatform rentalPlatform;

    address owner = address(1);
    address assetOwner = address(2);
    address borrower = address(3);

    uint256 constant RENTAL_FEE = 1 ether;
    uint256 constant SAFETY_BOND = 5 ether;

    function setUp() public {
        vm.startPrank(owner);
        rentalPlatform = new RentalPlatform();
        vm.stopPrank();

        vm.deal(assetOwner, 10 ether);
        vm.deal(borrower, 10 ether);
    }

    /* ======================================================
            ASSET REGISTRATION
       ====================================================== */

    function testRegisterAsset() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Camera",
            "DSLR Camera",
            RENTAL_FEE,
            SAFETY_BOND
        );

        (
            address assetOwnerStored,
            ,
            ,
            uint256 fee,
            uint256 bond,
            bool available
        ) = rentalPlatform.getAsset(1);

        assertEq(assetOwnerStored, assetOwner);
        assertEq(fee, RENTAL_FEE);
        assertEq(bond, SAFETY_BOND);
        assertTrue(available);
    }

    /* ======================================================
            RENTAL CREATION
       ====================================================== */

    function testCreateRental() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Bike",
            "Mountain Bike",
            RENTAL_FEE,
            SAFETY_BOND
        );

        vm.prank(borrower);
        rentalPlatform.createRental{value: SAFETY_BOND}(1, 2);

        (
            ,
            address borrowerStored,
            ,
            ,
            ,
            ,
            ,
            ,
            RentalPlatform.RentalStatus status,
            
        ) = rentalPlatform.getRental(1);

        assertEq(borrowerStored, borrower);
        assertEq(uint256(status), uint256(RentalPlatform.RentalStatus.Pending));
    }

    function testFailCreateRentalWithWrongBond() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Laptop",
            "MacBook",
            RENTAL_FEE,
            SAFETY_BOND
        );

        vm.prank(borrower);
        rentalPlatform.createRental{value: 1 ether}(1, 1);
    }

    /* ======================================================
            PICKUP HANDSHAKE
       ====================================================== */

    function testPickupHandshakeActivatesRental() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Drone",
            "DJI",
            RENTAL_FEE,
            SAFETY_BOND
        );

        vm.prank(borrower);
        rentalPlatform.createRental{value: SAFETY_BOND}(1, 1);

        vm.prank(assetOwner);
        rentalPlatform.confirmPickup(1);

        vm.prank(borrower);
        rentalPlatform.confirmPickup(1);

        (
            ,
            ,
            uint256 startTime,
            ,
            ,
            ,
            ,
            ,
            RentalPlatform.RentalStatus status,
           

        ) = rentalPlatform.getRental(1);

        assertTrue(startTime > 0);
        assertEq(uint256(status), uint256(RentalPlatform.RentalStatus.Active));
    }

    /* ======================================================
            RETURN HANDSHAKE & COMPLETION
       ====================================================== */

    function testReturnCompletesRental() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Speaker",
            "JBL",
            RENTAL_FEE,
            SAFETY_BOND
        );

        vm.prank(borrower);
        rentalPlatform.createRental{value: SAFETY_BOND}(1, 1);

        vm.prank(assetOwner);
        rentalPlatform.confirmPickup(1);
        vm.prank(borrower);
        rentalPlatform.confirmPickup(1);

        vm.prank(assetOwner);
        rentalPlatform.confirmReturn(1);
        vm.prank(borrower);
        rentalPlatform.confirmReturn(1);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            RentalPlatform.RentalStatus status,
           
        ) = rentalPlatform.getRental(1);

        assertEq(uint256(status), uint256(RentalPlatform.RentalStatus.Completed));
    }

    /* ======================================================
            LATE PENALTY
       ====================================================== */

    function testLatePenaltyApplied() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Projector",
            "HD",
            RENTAL_FEE,
            SAFETY_BOND
        );

        vm.prank(borrower);
        rentalPlatform.createRental{value: SAFETY_BOND}(1, 1);

        vm.prank(assetOwner);
        rentalPlatform.confirmPickup(1);
        vm.prank(borrower);
        rentalPlatform.confirmPickup(1);

        // Move time forward (2 days)
        vm.warp(block.timestamp + 2 days);

        vm.prank(assetOwner);
        rentalPlatform.confirmReturn(1);
        vm.prank(borrower);
        rentalPlatform.confirmReturn(1);

        uint256 penalty = rentalPlatform.calculateLatePenalty(1);
        assertTrue(penalty > 0);
    }

    /* ======================================================
            CANCELLATION
       ====================================================== */

    function testCancelRental() public {
        vm.prank(assetOwner);
        rentalPlatform.registerAsset(
            "Tablet",
            "iPad",
            RENTAL_FEE,
            SAFETY_BOND
        );

        vm.prank(borrower);
        rentalPlatform.createRental{value: SAFETY_BOND}(1, 2);

        vm.prank(borrower);
        rentalPlatform.cancelRental(1);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            RentalPlatform.RentalStatus status,
           
        ) = rentalPlatform.getRental(1);

        assertEq(uint256(status), uint256(RentalPlatform.RentalStatus.Cancelled));
    }
}