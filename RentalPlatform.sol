// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RentalPlatform - Gas Optimized
 * @dev P2P rental platform for physical assets with optimized gas costs
 * 
 * IMPLEMENTATION STATUS:
 * ✅ Phase 1: Asset Registry - COMPLETED
 * ✅ Phase 2-C: Dual Pickup Confirmation with Handshake - COMPLETED
 * ✅ Phase 2-D: Return Confirmation Logic - COMPLETED
 * ✅ Gas Optimization - COMPLETED
 * 
 * GAS OPTIMIZATIONS APPLIED:
 * - Custom errors instead of require strings (20-30% savings on reverts)
 * - Storage variable packing (reduced storage slots)
 * - Memory caching of storage variables (reduced SLOAD operations)
 * - External visibility for functions called externally only
 * - Calldata for read-only array/string parameters
 * - Unchecked arithmetic where overflow is impossible
 * - Optimized loops with cached length
 * - Removed redundant storage operations
 */
contract RentalPlatform {
    
    // ============================================
    // CUSTOM ERRORS (Gas efficient)
    // ============================================
    
    error AssetDoesNotExist();
    error RentalDoesNotExist();
    error OnlyAssetOwner();
    error OnlyOwnerOrBorrower();
    error NameCannotBeEmpty();
    error ValueMustBeGreaterThanZero();
    error AssetNotAvailable();
    error CannotRentOwnAsset();
    error DurationMustBeGreaterThanZero();
    error IncorrectBondAmount();
    error AssetIsRented();
    error NoActiveRental();
    error RentalNotPending();
    error AlreadyConfirmedPickup();
    error RentalNotActive();
    error OnlyOwnerCanConfirmReturn();
    error BothPartiesMustConfirm();
    error RentalAlreadyStarted();
    
    // ============================================
    // STATE VARIABLES (Packed for gas efficiency)
    // ============================================
    
    // Slot 1: Owner address (20 bytes) + assetCount (12 bytes fits in same slot)
    address public contractOwner;
    uint96 public assetCount;
    
    // Slot 2: rentalCount
    uint256 public rentalCount;
    
    // Constants (not stored in storage)
    uint256 private constant LATE_PENALTY_RATE = 5;
    uint256 private constant PENALTY_TIME_UNIT = 1 hours;
    int256 private constant REPUTATION_REWARD = 5;
    int256 private constant REPUTATION_PENALTY = 10;
    
    // Packed struct for PhysicalAsset (optimized layout)
    struct PhysicalAsset {
        address owner;          // 20 bytes - Slot 0
        uint96 rentalFee;      // 12 bytes - Slot 0 (packed with owner)
        uint96 safetyBond;     // 12 bytes - Slot 1
        bool isAvailable;      // 1 byte   - Slot 1 (packed with safetyBond)
        string name;           // Slot 2
        string description;    // Slot 3
    }
    
    enum RentalStatus { Pending, Active, Completed, Disputed, Cancelled }
    
    // Packed struct for RentalAgreement
    struct RentalAgreement {
        uint96 assetId;           // 12 bytes - Slot 0
        address borrower;         // 20 bytes - Slot 0 (packed)
        uint64 startTime;         // 8 bytes  - Slot 1
        uint64 endTime;           // 8 bytes  - Slot 1 (packed)
        uint64 actualReturnTime;  // 8 bytes  - Slot 1 (packed)
        uint32 rentalDuration;    // 4 bytes  - Slot 1 (packed)
        RentalStatus status;      // 1 byte   - Slot 1 (packed)
    }
    
    mapping(uint256 => PhysicalAsset) public assets;
    mapping(uint256 => RentalAgreement) public rentals;
    mapping(uint256 => uint256) public activeRentalForAsset;
    mapping(uint256 => uint8) public handshakeCount;  // uint8 is enough (max value 2)
    mapping(uint256 => mapping(address => bool)) public hasConfirmedPickup;
    mapping(address => uint256) public safetyBondsLocked;
    mapping(address => int256) public reputationScore;
    mapping(address => uint256) public totalRentalsCompleted;
    
    // ============================================
    // EVENTS (Optimized - only essential indexed)
    // ============================================
    
    event AssetRegistered(uint256 indexed assetId, address indexed owner);
    event AssetUpdated(uint256 indexed assetId);
    event RentalCreated(uint256 indexed rentalId, uint256 indexed assetId, address borrower);
    event PickupConfirmed(uint256 indexed assetId, address confirmer);
    event RentalStarted(uint256 indexed rentalId);
    event ReturnConfirmed(uint256 indexed assetId);
    event RentalCompleted(uint256 indexed rentalId, bool wasLate);
    event SafetyBondLocked(address indexed borrower, uint256 amount);
    event SafetyBondReleased(address indexed borrower, uint256 returned);
    event ReputationUpdated(address indexed user, int256 newScore);
    
    // ============================================
    // MODIFIERS
    // ============================================
    
    modifier assetExists(uint256 _assetId) {
        if (_assetId == 0 || _assetId > assetCount) revert AssetDoesNotExist();
        _;
    }
    
    modifier rentalExists(uint256 _rentalId) {
        if (_rentalId == 0 || _rentalId > rentalCount) revert RentalDoesNotExist();
        _;
    }
    
    modifier onlyAssetOwner(uint256 _assetId) {
        if (assets[_assetId].owner != msg.sender) revert OnlyAssetOwner();
        _;
    }
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor() {
        contractOwner = msg.sender;
    }
    
    // ============================================
    // PHASE 1: ASSET REGISTRY FUNCTIONS
    // ============================================
    
    function registerAsset(
        string calldata _name,
        string calldata _description,
        uint96 _rentalFee,
        uint96 _safetyBond
    ) external returns (uint256) {
        if (bytes(_name).length == 0) revert NameCannotBeEmpty();
        if (_rentalFee == 0 || _safetyBond == 0) revert ValueMustBeGreaterThanZero();
        
        unchecked {
            ++assetCount;
        }
        
        uint256 newAssetId = assetCount;
        
        assets[newAssetId] = PhysicalAsset({
            owner: msg.sender,
            name: _name,
            description: _description,
            rentalFee: _rentalFee,
            safetyBond: _safetyBond,
            isAvailable: true
        });
        
        emit AssetRegistered(newAssetId, msg.sender);
        return newAssetId;
    }
    
    function updateAssetPricing(uint256 _assetId, uint96 _rentalFee, uint96 _safetyBond) 
        external assetExists(_assetId) onlyAssetOwner(_assetId) {
        if (_rentalFee == 0 || _safetyBond == 0) revert ValueMustBeGreaterThanZero();
        if (activeRentalForAsset[_assetId] != 0) revert AssetIsRented();
        
        PhysicalAsset storage asset = assets[_assetId];
        asset.rentalFee = _rentalFee;
        asset.safetyBond = _safetyBond;
        
        emit AssetUpdated(_assetId);
    }
    
    function updateAssetDescription(uint256 _assetId, string calldata _description) 
        external assetExists(_assetId) onlyAssetOwner(_assetId) {
        assets[_assetId].description = _description;
    }
    
    function setAssetAvailability(uint256 _assetId, bool _isAvailable) 
        external assetExists(_assetId) onlyAssetOwner(_assetId) {
        if (activeRentalForAsset[_assetId] != 0) revert AssetIsRented();
        assets[_assetId].isAvailable = _isAvailable;
    }
    
    // ============================================
    // RENTAL CREATION
    // ============================================
    
    function createRental(uint256 _assetId, uint32 _rentalDuration) 
        external payable assetExists(_assetId) returns (uint256) {
        PhysicalAsset storage asset = assets[_assetId];
        
        if (!asset.isAvailable) revert AssetNotAvailable();
        if (asset.owner == msg.sender) revert CannotRentOwnAsset();
        if (_rentalDuration == 0) revert DurationMustBeGreaterThanZero();
        if (msg.value != asset.safetyBond) revert IncorrectBondAmount();
        
        unchecked {
            ++rentalCount;
        }
        
        uint256 newRentalId = rentalCount;
        uint64 endTime = uint64(block.timestamp + (_rentalDuration * 1 days));
        
        rentals[newRentalId] = RentalAgreement({
            assetId: uint96(_assetId),
            borrower: msg.sender,
            startTime: 0,
            endTime: endTime,
            status: RentalStatus.Pending,
            actualReturnTime: 0,
            rentalDuration: _rentalDuration
        });
        
        // Update state
        safetyBondsLocked[msg.sender] += msg.value;
        asset.isAvailable = false;
        activeRentalForAsset[_assetId] = newRentalId;
        handshakeCount[_assetId] = 0;
        
        emit RentalCreated(newRentalId, _assetId, msg.sender);
        emit SafetyBondLocked(msg.sender, msg.value);
        
        return newRentalId;
    }
    
    // ============================================
    // PHASE 2-C: PICKUP CONFIRMATION LOGIC
    // ============================================
    
    function confirmPickup(uint256 _assetId) external assetExists(_assetId) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement storage rental = rentals[rentalId];
        PhysicalAsset storage asset = assets[_assetId];
        
        if (rental.status != RentalStatus.Pending) revert RentalNotPending();
        
        address caller = msg.sender;
        if (caller != asset.owner && caller != rental.borrower) revert OnlyOwnerOrBorrower();
        if (hasConfirmedPickup[_assetId][caller]) revert AlreadyConfirmedPickup();
        
        hasConfirmedPickup[_assetId][caller] = true;
        unchecked {
            ++handshakeCount[_assetId];
        }
        
        emit PickupConfirmed(_assetId, caller);
    }
    
    function startRental(uint256 _assetId) external assetExists(_assetId) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement storage rental = rentals[rentalId];
        
        if (rental.status != RentalStatus.Pending) revert RentalAlreadyStarted();
        if (handshakeCount[_assetId] != 2) revert BothPartiesMustConfirm();
        
        rental.startTime = uint64(block.timestamp);
        rental.status = RentalStatus.Active;
        
        emit RentalStarted(rentalId);
    }
    
    // ============================================
    // PHASE 2-D: RETURN CONFIRMATION LOGIC
    // ============================================
    
    function confirmReturn(uint256 _assetId) external assetExists(_assetId) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement storage rental = rentals[rentalId];
        PhysicalAsset storage asset = assets[_assetId];
        
        if (rental.status != RentalStatus.Active) revert RentalNotActive();
        if (msg.sender != asset.owner) revert OnlyOwnerCanConfirmReturn();
        
        rental.actualReturnTime = uint64(block.timestamp);
        rental.status = RentalStatus.Completed;
        
        emit ReturnConfirmed(_assetId);
        
        _processReturnPayment(rentalId, _assetId, rental, asset);
    }
    
    function _processReturnPayment(
        uint256 _rentalId,
        uint256 _assetId,
        RentalAgreement storage rental,
        PhysicalAsset storage asset
    ) private {
        // Cache values in memory
        address borrower = rental.borrower;
        address owner = asset.owner;
        uint256 safetyBond = asset.safetyBond;
        uint256 actualReturn = rental.actualReturnTime;
        uint256 deadline = rental.endTime;
        
        // Calculate rental fee
        uint256 totalRentalFee;
        unchecked {
            totalRentalFee = uint256(asset.rentalFee) * uint256(rental.rentalDuration);
        }
        
        // Calculate late penalty
        uint256 penaltyAmount = 0;
        bool wasLate = actualReturn > deadline;
        
        if (wasLate) {
            uint256 lateTime;
            unchecked {
                lateTime = actualReturn - deadline;
            }
            
            uint256 lateUnits = (lateTime / PENALTY_TIME_UNIT) + 1;
            
            unchecked {
                penaltyAmount = (safetyBond * LATE_PENALTY_RATE * lateUnits) / 100;
            }
            
            if (penaltyAmount > safetyBond) {
                penaltyAmount = safetyBond;
            }
        }
        
        // Calculate total charge
        uint256 totalCharge;
        unchecked {
            totalCharge = totalRentalFee + penaltyAmount;
        }
        
        if (totalCharge > safetyBond) {
            totalCharge = safetyBond;
        }
        
        uint256 amountToReturn;
        unchecked {
            amountToReturn = safetyBond - totalCharge;
        }
        
        // Update state
        safetyBondsLocked[borrower] -= safetyBond;
        asset.isAvailable = true;
        activeRentalForAsset[_assetId] = 0;
        handshakeCount[_assetId] = 0;
        
        unchecked {
            ++totalRentalsCompleted[borrower];
            ++totalRentalsCompleted[owner];
        }
        
        // Transfer payments
        payable(owner).transfer(totalCharge);
        if (amountToReturn > 0) {
            payable(borrower).transfer(amountToReturn);
        }
        
        // Update reputation
        _updateReputationScores(borrower, owner, wasLate);
        
        emit SafetyBondReleased(borrower, amountToReturn);
        emit RentalCompleted(_rentalId, wasLate);
    }
    
    function _updateReputationScores(address _borrower, address _owner, bool _wasLate) private {
        if (_wasLate) {
            reputationScore[_borrower] -= REPUTATION_PENALTY;
            emit ReputationUpdated(_borrower, reputationScore[_borrower]);
        } else {
            reputationScore[_borrower] += REPUTATION_REWARD;
            emit ReputationUpdated(_borrower, reputationScore[_borrower]);
        }
        
        reputationScore[_owner] += REPUTATION_REWARD;
        emit ReputationUpdated(_owner, reputationScore[_owner]);
    }
    
    // ============================================
    // VIEW FUNCTIONS (Gas optimized)
    // ============================================
    
    function getAsset(uint256 _assetId) external view assetExists(_assetId)
        returns (address owner, string memory name, string memory description, uint96 rentalFee, uint96 safetyBond, bool isAvailable) {
        PhysicalAsset memory a = assets[_assetId];
        return (a.owner, a.name, a.description, a.rentalFee, a.safetyBond, a.isAvailable);
    }
    
    function getRental(uint256 _rentalId) external view rentalExists(_rentalId)
        returns (uint96, address, uint64, uint64, RentalStatus, uint64, uint32) {
        RentalAgreement memory r = rentals[_rentalId];
        return (r.assetId, r.borrower, r.startTime, r.endTime, r.status, r.actualReturnTime, r.rentalDuration);
    }
    
    function getRentalByAsset(uint256 _assetId) external view assetExists(_assetId)
        returns (uint96, address, uint64, uint64, RentalStatus, uint64, uint32) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement memory r = rentals[rentalId];
        return (r.assetId, r.borrower, r.startTime, r.endTime, r.status, r.actualReturnTime, r.rentalDuration);
    }
    
    function getHandshakeStatus(uint256 _assetId) external view assetExists(_assetId)
        returns (uint8 count, bool ownerConfirmed, bool borrowerConfirmed) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement memory rental = rentals[rentalId];
        PhysicalAsset memory asset = assets[_assetId];
        
        return (
            handshakeCount[_assetId],
            hasConfirmedPickup[_assetId][asset.owner],
            hasConfirmedPickup[_assetId][rental.borrower]
        );
    }
    
    function isRentalLate(uint256 _assetId) external view assetExists(_assetId) returns (bool) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) return false;
        
        RentalAgreement memory r = rentals[rentalId];
        return r.status == RentalStatus.Active && block.timestamp > r.endTime;
    }
    
    function calculateLatePenalty(uint256 _assetId) external view assetExists(_assetId) returns (uint256) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement memory rental = rentals[rentalId];
        
        if (block.timestamp <= rental.endTime) return 0;
        
        PhysicalAsset memory asset = assets[_assetId];
        
        uint256 lateTime;
        unchecked {
            lateTime = block.timestamp - rental.endTime;
        }
        
        uint256 lateUnits = (lateTime / PENALTY_TIME_UNIT) + 1;
        uint256 penalty;
        
        unchecked {
            penalty = (uint256(asset.safetyBond) * LATE_PENALTY_RATE * lateUnits) / 100;
        }
        
        if (penalty > asset.safetyBond) {
            penalty = asset.safetyBond;
        }
        
        return penalty;
    }
    
    function calculateTotalCharges(uint256 _assetId) external view assetExists(_assetId) 
        returns (uint256 rentalFee, uint256 penalty, uint256 total) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) revert NoActiveRental();
        
        RentalAgreement memory rental = rentals[rentalId];
        PhysicalAsset memory asset = assets[_assetId];
        
        unchecked {
            rentalFee = uint256(asset.rentalFee) * uint256(rental.rentalDuration);
        }
        
        penalty = 0;
        
        if (rental.status == RentalStatus.Active && block.timestamp > rental.endTime) {
            uint256 lateTime;
            unchecked {
                lateTime = block.timestamp - rental.endTime;
            }
            
            uint256 lateUnits = (lateTime / PENALTY_TIME_UNIT) + 1;
            
            unchecked {
                penalty = (uint256(asset.safetyBond) * LATE_PENALTY_RATE * lateUnits) / 100;
            }
            
            if (penalty > asset.safetyBond) {
                penalty = asset.safetyBond;
            }
        }
        
        unchecked {
            total = rentalFee + penalty;
        }
        
        if (total > asset.safetyBond) {
            total = asset.safetyBond;
        }
        
        return (rentalFee, penalty, total);
    }
    
    function getUserReputation(address _user) external view returns (int256, uint256) {
        return (reputationScore[_user], totalRentalsCompleted[_user]);
    }
    
    function getAvailableAssets() external view returns (uint256[] memory) {
        uint256 count = assetCount;
        uint256 availableCount = 0;
        
        // First pass: count available assets
        for (uint256 i = 1; i <= count;) {
            if (assets[i].isAvailable) {
                unchecked { ++availableCount; }
            }
            unchecked { ++i; }
        }
        
        // Second pass: populate array
        uint256[] memory available = new uint256[](availableCount);
        uint256 idx = 0;
        
        for (uint256 i = 1; i <= count;) {
            if (assets[i].isAvailable) {
                available[idx] = i;
                unchecked { ++idx; }
            }
            unchecked { ++i; }
        }
        
        return available;
    }
    
    function getAssetsByOwner(address _owner) external view returns (uint256[] memory) {
        uint256 count = assetCount;
        uint256 ownerCount = 0;
        
        // First pass: count owner's assets
        for (uint256 i = 1; i <= count;) {
            if (assets[i].owner == _owner) {
                unchecked { ++ownerCount; }
            }
            unchecked { ++i; }
        }
        
        // Second pass: populate array
        uint256[] memory owned = new uint256[](ownerCount);
        uint256 idx = 0;
        
        for (uint256 i = 1; i <= count;) {
            if (assets[i].owner == _owner) {
                owned[idx] = i;
                unchecked { ++idx; }
            }
            unchecked { ++i; }
        }
        
        return owned;
    }
}
