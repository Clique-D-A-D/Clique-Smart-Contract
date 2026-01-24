// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./asset-registry.sol";

contract RentalPlatformTest {
    RentalPlatform public platform;
    
    // Test addresses (mock users)
    address constant OWNER = address(0x123);
    address constant NON_OWNER = address(0x456);

    // This runs before every test case
    function beforeEach() public {
        platform = new RentalPlatform();
    }

    // --- TEST REGISTRATION ---
    
    function testRegisterAsset() public {
        uint256 id = platform.registerAsset("Drill", "Power tool", 100, 500);
        
        (address owner, string memory name,,, uint256 bond, bool available) = platform.getAsset(id);

// Using the variables makes the warning go away
        assert(owner == address(this));
        assert(keccak256(bytes(name)) == keccak256(bytes("Drill"))); 
        assert(bond == 500);
        assert(available == true);
    }

    // --- TEST PRICING UPDATES ---

    function testUpdatePricing() public {
        uint256 id = platform.registerAsset("Camera", "DSLR", 100, 500);
        
        platform.updateAssetPricing(id, 200, 1000);
        
        (,,, uint256 fee, uint256 bond,) = platform.getAsset(id);
        assert(fee == 200);
        assert(bond == 1000);
    }

    // --- TEST AVAILABILITY TOGGLE ---

    function testToggleAvailability() public {
        uint256 id = platform.registerAsset("Bike", "Mountain bike", 50, 200);
        
        platform.setAssetAvailability(id, false);
        bool status = platform.isAssetAvailable(id);
        
        assert(status == false);
    }

    // --- TEST VIEW FILTERS ---

    function testGetAvailableAssets() public {
        platform.registerAsset("Item 1", "Desc 1", 10, 10);
        platform.registerAsset("Item 2", "Desc 2", 10, 10);
        
        platform.setAssetAvailability(1, false); // Hide item 1
        
        uint256[] memory available = platform.getAvailableAssets();
        
        assert(available.length == 1);
        assert(available[0] == 2);
    }
}