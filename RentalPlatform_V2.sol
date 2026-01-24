// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title RentalPlatform
 * @dev Complete P2P rental platform for physical assets
 * 
 * FEATURES IMPLEMENTED:
 * ✅ Asset Registry - Register, update, and manage rental items
 * ✅ Dual Handshake Mechanism - Both parties confirm pickup/return
 * ✅ Collateral Management - Safety bonds locked and released automatically
 * ✅ Payment Processing - Automatic fee deduction and distribution
 * ✅ Late Penalty System - 5% per hour penalty for late returns
 * ✅ Reputation Tracking - Score updates based on rental performance
 */
contract RentalPlatform {
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    struct PhysicalAsset {
        address owner;
        string name;
        string description;
        uint256 rentalFee;      // Per day in Wei
        uint256 safetyBond;
        bool isAvailable;
    }
    
    enum RentalStatus { Pending, Active, Completed, Disputed, Cancelled }
    
    struct RentalAgreement {
        uint256 assetId;
        address borrower;
        uint256 startTime;
        uint256 endTime;
        bool ownerPickedUp;
        bool borrowerPickedUp;
        bool ownerReturned;
        bool borrowerReturned;
        RentalStatus status;
        uint256 actualReturnTime;
        uint256 rentalDuration;
    }
    
    mapping(uint256 => PhysicalAsset) public assets;
    mapping(uint256 => RentalAgreement) public rentals;
    mapping(uint256 => uint256) public activeRentalForAsset;
    mapping(address => uint256) public safetyBondsLocked;
    mapping(address => int256) public reputationScore;
    mapping(address => uint256) public totalRentalsCompleted;
    
    uint256 public assetCount;
    uint256 public rentalCount;
    address public contractOwner;
    
    uint256 public constant LATE_PENALTY_RATE = 5;
    uint256 public constant PENALTY_TIME_UNIT = 1 hours;
    int256 public constant REPUTATION_REWARD = 5;
    int256 public constant REPUTATION_PENALTY = 10;
    
    // ============================================
    // EVENTS
    // ============================================
    
    event AssetRegistered(uint256 indexed assetId, address indexed owner, string name, uint256 rentalFee, uint256 safetyBond);
    event AssetUpdated(uint256 indexed assetId, uint256 rentalFee, uint256 safetyBond);
    event RentalCreated(uint256 indexed rentalId, uint256 indexed assetId, address indexed borrower, uint256 endTime);
    event PickupConfirmed(uint256 indexed rentalId, address indexed confirmer, bool isOwner);
    event RentalActivated(uint256 indexed rentalId, uint256 startTime);
    event ReturnConfirmed(uint256 indexed rentalId, address indexed confirmer, bool isOwner);
    event RentalCompleted(uint256 indexed rentalId, uint256 totalCharge, uint256 penalty, bool wasLate);
    event RentalCancelled(uint256 indexed rentalId);
    event SafetyBondLocked(address indexed borrower, uint256 amount);
    event SafetyBondReleased(address indexed borrower, uint256 returned, uint256 deducted);
    event ReputationUpdated(address indexed user, int256 newScore, int256 change);
    
    // ============================================
    // MODIFIERS
    // ============================================
    
    modifier assetExists(uint256 _assetId) {
        require(_assetId > 0 && _assetId <= assetCount, "Asset does not exist");
        _;
    }
    
    modifier rentalExists(uint256 _rentalId) {
        require(_rentalId > 0 && _rentalId <= rentalCount, "Rental does not exist");
        _;
    }
    
    modifier onlyAssetOwner(uint256 _assetId) {
        require(assets[_assetId].owner == msg.sender, "Only asset owner");
        _;
    }
    
    modifier onlyRentalParticipant(uint256 _rentalId) {
        require(
            msg.sender == assets[rentals[_rentalId].assetId].owner || 
            msg.sender == rentals[_rentalId].borrower,
            "Only rental participants"
        );
        _;
    }
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor() {
        contractOwner = msg.sender;
    }
    
    // ============================================
    // ASSET REGISTRY FUNCTIONS
    // ============================================
    
    function registerAsset(
        string memory _name,
        string memory _description,
        uint256 _rentalFee,
        uint256 _safetyBond
    ) public returns (uint256) {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_rentalFee > 0, "Rental fee must be > 0");
        require(_safetyBond > 0, "Safety bond must be > 0");
        
        assetCount++;
        assets[assetCount] = PhysicalAsset({
            owner: msg.sender,
            name: _name,
            description: _description,
            rentalFee: _rentalFee,
            safetyBond: _safetyBond,
            isAvailable: true
        });
        
        emit AssetRegistered(assetCount, msg.sender, _name, _rentalFee, _safetyBond);
        return assetCount;
    }
    
    function updateAssetPricing(uint256 _assetId, uint256 _rentalFee, uint256 _safetyBond) 
        public assetExists(_assetId) onlyAssetOwner(_assetId) {
        require(_rentalFee > 0 && _safetyBond > 0, "Values must be > 0");
        require(activeRentalForAsset[_assetId] == 0, "Asset is rented");
        
        assets[_assetId].rentalFee = _rentalFee;
        assets[_assetId].safetyBond = _safetyBond;
        emit AssetUpdated(_assetId, _rentalFee, _safetyBond);
    }
    
    function updateAssetDescription(uint256 _assetId, string memory _description) 
        public assetExists(_assetId) onlyAssetOwner(_assetId) {
        assets[_assetId].description = _description;
    }
    
    function setAssetAvailability(uint256 _assetId, bool _isAvailable) 
        public assetExists(_assetId) onlyAssetOwner(_assetId) {
        require(activeRentalForAsset[_assetId] == 0, "Asset is rented");
        assets[_assetId].isAvailable = _isAvailable;
    }
    
    // ============================================
    // RENTAL CREATION
    // ============================================
    
    function createRental(uint256 _assetId, uint256 _rentalDuration) 
        public payable assetExists(_assetId) returns (uint256) {
        PhysicalAsset storage asset = assets[_assetId];
        
        require(asset.isAvailable, "Asset not available");
        require(asset.owner != msg.sender, "Cannot rent own asset");
        require(_rentalDuration > 0, "Duration must be > 0");
        require(msg.value == asset.safetyBond, "Incorrect bond amount");
        
        rentalCount++;
        uint256 endTime = block.timestamp + (_rentalDuration * 1 days);
        
        rentals[rentalCount] = RentalAgreement({
            assetId: _assetId,
            borrower: msg.sender,
            startTime: 0,
            endTime: endTime,
            ownerPickedUp: false,
            borrowerPickedUp: false,
            ownerReturned: false,
            borrowerReturned: false,
            status: RentalStatus.Pending,
            actualReturnTime: 0,
            rentalDuration: _rentalDuration
        });
        
        safetyBondsLocked[msg.sender] += msg.value;
        asset.isAvailable = false;
        activeRentalForAsset[_assetId] = rentalCount;
        
        emit RentalCreated(rentalCount, _assetId, msg.sender, endTime);
        emit SafetyBondLocked(msg.sender, msg.value);
        
        return rentalCount;
    }
    
    // ============================================
    // PICKUP HANDSHAKE (Both parties must confirm)
    // ============================================
    
    function confirmPickup(uint256 _rentalId) 
        public rentalExists(_rentalId) onlyRentalParticipant(_rentalId) {
        RentalAgreement storage rental = rentals[_rentalId];
        require(rental.status == RentalStatus.Pending, "Not pending");
        
        bool isOwner = (msg.sender == assets[rental.assetId].owner);
        
        if (isOwner) {
            require(!rental.ownerPickedUp, "Already confirmed");
            rental.ownerPickedUp = true;
        } else {
            require(!rental.borrowerPickedUp, "Already confirmed");
            rental.borrowerPickedUp = true;
        }
        
        emit PickupConfirmed(_rentalId, msg.sender, isOwner);
        
        // Activate rental when both confirm
        if (rental.ownerPickedUp && rental.borrowerPickedUp) {
            rental.startTime = block.timestamp;
            rental.status = RentalStatus.Active;
            emit RentalActivated(_rentalId, rental.startTime);
        }
    }
    
    // ============================================
    // RETURN HANDSHAKE (Both parties must confirm)
    // ============================================
    
    function confirmReturn(uint256 _rentalId) 
        public rentalExists(_rentalId) onlyRentalParticipant(_rentalId) {
        RentalAgreement storage rental = rentals[_rentalId];
        require(rental.status == RentalStatus.Active, "Not active");
        
        bool isOwner = (msg.sender == assets[rental.assetId].owner);
        
        if (isOwner) {
            require(!rental.ownerReturned, "Already confirmed");
            rental.ownerReturned = true;
        } else {
            require(!rental.borrowerReturned, "Already confirmed");
            rental.borrowerReturned = true;
        }
        
        emit ReturnConfirmed(_rentalId, msg.sender, isOwner);
        
        // Complete rental when both confirm
        if (rental.ownerReturned && rental.borrowerReturned) {
            _completeRental(_rentalId);
        }
    }
    
    // ============================================
    // PAYMENT PROCESSING & LATE PENALTIES
    // ============================================
    
    function _completeRental(uint256 _rentalId) private {
        RentalAgreement storage rental = rentals[_rentalId];
        PhysicalAsset storage asset = assets[rental.assetId];
        
        rental.actualReturnTime = block.timestamp;
        rental.status = RentalStatus.Completed;
        
        // Calculate rental fee
        uint256 totalRentalFee = asset.rentalFee * rental.rentalDuration;
        
        // Calculate late penalty
        uint256 penaltyAmount = 0;
        bool wasLate = rental.actualReturnTime > rental.endTime;
        
        if (wasLate) {
            uint256 lateTime = rental.actualReturnTime - rental.endTime;
            uint256 lateUnits = (lateTime / PENALTY_TIME_UNIT) + 1;
            penaltyAmount = (asset.safetyBond * LATE_PENALTY_RATE * lateUnits) / 100;
            
            if (penaltyAmount > asset.safetyBond) {
                penaltyAmount = asset.safetyBond;
            }
        }
        
        // Calculate total charge
        uint256 totalCharge = totalRentalFee + penaltyAmount;
        if (totalCharge > asset.safetyBond) {
            totalCharge = asset.safetyBond;
        }
        
        uint256 amountToReturn = asset.safetyBond - totalCharge;
        
        // Update locked bonds
        safetyBondsLocked[rental.borrower] -= asset.safetyBond;
        
        // Transfer payments
        payable(asset.owner).transfer(totalCharge);
        if (amountToReturn > 0) {
            payable(rental.borrower).transfer(amountToReturn);
        }
        
        // Update reputation
        if (wasLate) {
            reputationScore[rental.borrower] -= REPUTATION_PENALTY;
            emit ReputationUpdated(rental.borrower, reputationScore[rental.borrower], -REPUTATION_PENALTY);
        } else {
            reputationScore[rental.borrower] += REPUTATION_REWARD;
            emit ReputationUpdated(rental.borrower, reputationScore[rental.borrower], REPUTATION_REWARD);
        }
        
        reputationScore[asset.owner] += REPUTATION_REWARD;
        emit ReputationUpdated(asset.owner, reputationScore[asset.owner], REPUTATION_REWARD);
        
        // Update counters
        totalRentalsCompleted[rental.borrower]++;
        totalRentalsCompleted[asset.owner]++;
        
        // Make asset available
        asset.isAvailable = true;
        activeRentalForAsset[rental.assetId] = 0;
        
        emit SafetyBondReleased(rental.borrower, amountToReturn, totalCharge);
        emit RentalCompleted(_rentalId, totalCharge, penaltyAmount, wasLate);
    }
    
    // ============================================
    // RENTAL CANCELLATION
    // ============================================
    
    function cancelRental(uint256 _rentalId) public rentalExists(_rentalId) {
        RentalAgreement storage rental = rentals[_rentalId];
        require(rental.status == RentalStatus.Pending, "Can only cancel pending");
        require(msg.sender == rental.borrower, "Only borrower can cancel");
        
        PhysicalAsset storage asset = assets[rental.assetId];
        uint256 bondAmount = asset.safetyBond;
        
        safetyBondsLocked[rental.borrower] -= bondAmount;
        asset.isAvailable = true;
        activeRentalForAsset[rental.assetId] = 0;
        rental.status = RentalStatus.Cancelled;
        
        payable(rental.borrower).transfer(bondAmount);
        
        emit RentalCancelled(_rentalId);
        emit SafetyBondReleased(rental.borrower, bondAmount, 0);
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    function getAsset(uint256 _assetId) public view assetExists(_assetId)
        returns (address, string memory, string memory, uint256, uint256, bool) {
        PhysicalAsset memory a = assets[_assetId];
        return (a.owner, a.name, a.description, a.rentalFee, a.safetyBond, a.isAvailable);
    }
    
    function getRental(uint256 _rentalId) public view rentalExists(_rentalId)
        returns (uint256, address, uint256, uint256, bool, bool, bool, bool, RentalStatus, uint256) {
        RentalAgreement memory r = rentals[_rentalId];
        return (r.assetId, r.borrower, r.startTime, r.endTime, 
                r.ownerPickedUp, r.borrowerPickedUp, r.ownerReturned, 
                r.borrowerReturned, r.status, r.actualReturnTime);
    }
    
    function isRentalLate(uint256 _rentalId) public view rentalExists(_rentalId) returns (bool) {
        RentalAgreement memory r = rentals[_rentalId];
        return r.status == RentalStatus.Active && block.timestamp > r.endTime;
    }
    
    function calculateLatePenalty(uint256 _rentalId) public view rentalExists(_rentalId) returns (uint256) {
        RentalAgreement memory r = rentals[_rentalId];
        if (block.timestamp <= r.endTime) return 0;
        
        uint256 lateTime = block.timestamp - r.endTime;
        uint256 lateUnits = (lateTime / PENALTY_TIME_UNIT) + 1;
        uint256 penalty = (assets[r.assetId].safetyBond * LATE_PENALTY_RATE * lateUnits) / 100;
        
        if (penalty > assets[r.assetId].safetyBond) {
            penalty = assets[r.assetId].safetyBond;
        }
        return penalty;
    }
    
    function getUserReputation(address _user) public view returns (int256, uint256) {
        return (reputationScore[_user], totalRentalsCompleted[_user]);
    }
    
    function getAvailableAssets() public view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= assetCount; i++) {
            if (assets[i].isAvailable) count++;
        }
        
        uint256[] memory available = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= assetCount; i++) {
            if (assets[i].isAvailable) {
                available[idx] = i;
                idx++;
            }
        }
        return available;
    }
    
    function getAssetsByOwner(address _owner) public view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= assetCount; i++) {
            if (assets[i].owner == _owner) count++;
        }
        
        uint256[] memory owned = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= assetCount; i++) {
            if (assets[i].owner == _owner) {
                owned[idx] = i;
                idx++;
            }
        }
        return owned;
    }
}
