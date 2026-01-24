// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title RentalPlatform
 * @dev P2P rental platform for physical assets
 * 
 * IMPLEMENTATION STATUS:
 * ✅ Phase 1: Asset Registry - COMPLETED
 * ✅ Phase 2-C: Dual Pickup Confirmation with Handshake - COMPLETED
 * ⏳ Phase 2-D: Return Confirmation Logic - PENDING
 */
contract RentalPlatform {
    
    // ============================================
    // STATE VARIABLES - ASSET REGISTRY
    // ============================================
    
    struct PhysicalAsset {
        address owner;
        string name;
        string description;
        uint256 rentalFee;      // Per day in Wei
        uint256 safetyBond;
        bool isAvailable;
    }
    
    mapping(uint256 => PhysicalAsset) public assets;
    uint256 public assetCount;
    address public contractOwner;
    
    // ============================================
    // STATE VARIABLES - RENTAL AGREEMENTS
    // ============================================
    
    enum RentalStatus { Pending, Active, Completed, Disputed, Cancelled }
    
    struct RentalAgreement {
        uint256 assetId;
        address borrower;
        uint256 startTime;
        uint256 endTime;
        RentalStatus status;
        uint256 actualReturnTime;
        uint256 rentalDuration;
    }
    
    mapping(uint256 => RentalAgreement) public rentals;
    uint256 public rentalCount;
    
    // Track active rental for each asset
    mapping(uint256 => uint256) public activeRentalForAsset;
    
    // ============================================
    // STATE VARIABLES - PHASE 2-C: HANDSHAKE LOGIC
    // ============================================
    
    // Handshake count for pickup confirmation (assetId => count)
    mapping(uint256 => uint256) public handshakeCount;
    
    // Track who has confirmed pickup
    mapping(uint256 => mapping(address => bool)) public hasConfirmedPickup;
    
    // ============================================
    // STATE VARIABLES - COLLATERAL & REPUTATION
    // ============================================
    
    mapping(address => uint256) public safetyBondsLocked;
    mapping(address => int256) public reputationScore;
    mapping(address => uint256) public totalRentalsCompleted;
    
    // ============================================
    // CONSTANTS
    // ============================================
    
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
    event PickupConfirmed(uint256 indexed assetId, address indexed confirmer, uint256 currentCount);
    event RentalStarted(uint256 indexed rentalId, uint256 indexed assetId, uint256 startTime);
    event SafetyBondLocked(address indexed borrower, uint256 amount);
    
    // Phase 2-D events (to be used later)
    event ReturnConfirmed(uint256 indexed assetId, address indexed owner);
    event RentalCompleted(uint256 indexed rentalId, uint256 totalCharge, uint256 penalty, bool wasLate);
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
            startTime: 0,  // Will be set when startRental is called
            endTime: endTime,
            status: RentalStatus.Pending,
            actualReturnTime: 0,
            rentalDuration: _rentalDuration
        });
        
        // Lock safety bond
        safetyBondsLocked[msg.sender] += msg.value;
        
        // Mark asset as unavailable
        asset.isAvailable = false;
        
        // Track active rental
        activeRentalForAsset[_assetId] = rentalCount;
        
        // Reset handshake count for this asset
        handshakeCount[_assetId] = 0;
        hasConfirmedPickup[_assetId][asset.owner] = false;
        hasConfirmedPickup[_assetId][msg.sender] = false;
        
        emit RentalCreated(rentalCount, _assetId, msg.sender, endTime);
        emit SafetyBondLocked(msg.sender, msg.value);
        
        return rentalCount;
    }
    
    // ============================================
    // PHASE 2-C: PICKUP CONFIRMATION LOGIC
    // ============================================
    
    /**
     * @dev Confirm pickup - Part 1 of Dual Handshake
     * Increments handshakeCount and checks if caller is owner or borrower
     * @param _assetId ID of the asset being rented
     */
    function confirmPickup(uint256 _assetId) public assetExists(_assetId) {
        // Get active rental for this asset
        uint256 rentalId = activeRentalForAsset[_assetId];
        require(rentalId > 0, "No active rental for this asset");
        
        RentalAgreement storage rental = rentals[rentalId];
        PhysicalAsset storage asset = assets[_assetId];
        
        require(rental.status == RentalStatus.Pending, "Rental is not pending");
        
        // Check if caller is owner or borrower
        require(
            msg.sender == asset.owner || msg.sender == rental.borrower,
            "Only owner or borrower can confirm"
        );
        
        // Check if this person already confirmed
        require(!hasConfirmedPickup[_assetId][msg.sender], "Already confirmed pickup");
        
        // Mark as confirmed and increment handshake count
        hasConfirmedPickup[_assetId][msg.sender] = true;
        handshakeCount[_assetId]++;
        
        emit PickupConfirmed(_assetId, msg.sender, handshakeCount[_assetId]);
    }
    
    /**
     * @dev Start rental - Part 2 of Dual Handshake
     * Triggered only when handshakeCount == 2
     * The rental period starts only after dual confirmation
     * @param _assetId ID of the asset being rented
     */
    function startRental(uint256 _assetId) public assetExists(_assetId) {
        // Get active rental for this asset
        uint256 rentalId = activeRentalForAsset[_assetId];
        require(rentalId > 0, "No active rental for this asset");
        
        RentalAgreement storage rental = rentals[rentalId];
        
        require(rental.status == RentalStatus.Pending, "Rental already started or completed");
        require(handshakeCount[_assetId] == 2, "Both parties must confirm pickup first");
        
        // Start the rental period
        rental.startTime = block.timestamp;
        rental.status = RentalStatus.Active;
        
        emit RentalStarted(rentalId, _assetId, rental.startTime);
    }
    
    // ============================================
    // PHASE 2-D: RETURN CONFIRMATION (TO BE IMPLEMENTED)
    // ============================================
    
    // TODO: Implement confirmReturn() function
    // TODO: Implement late penalty calculation
    // TODO: Implement payment distribution
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    function getAsset(uint256 _assetId) public view assetExists(_assetId)
        returns (address, string memory, string memory, uint256, uint256, bool) {
        PhysicalAsset memory a = assets[_assetId];
        return (a.owner, a.name, a.description, a.rentalFee, a.safetyBond, a.isAvailable);
    }
    
    function getRental(uint256 _rentalId) public view rentalExists(_rentalId)
        returns (uint256, address, uint256, uint256, RentalStatus, uint256, uint256) {
        RentalAgreement memory r = rentals[_rentalId];
        return (r.assetId, r.borrower, r.startTime, r.endTime, r.status, r.actualReturnTime, r.rentalDuration);
    }
    
    function getRentalByAsset(uint256 _assetId) public view assetExists(_assetId)
        returns (uint256, address, uint256, uint256, RentalStatus, uint256, uint256) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        require(rentalId > 0, "No active rental for this asset");
        return getRental(rentalId);
    }
    
    function getHandshakeStatus(uint256 _assetId) public view assetExists(_assetId)
        returns (uint256 count, bool ownerConfirmed, bool borrowerConfirmed) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        require(rentalId > 0, "No active rental for this asset");
        
        RentalAgreement memory rental = rentals[rentalId];
        PhysicalAsset memory asset = assets[_assetId];
        
        return (
            handshakeCount[_assetId],
            hasConfirmedPickup[_assetId][asset.owner],
            hasConfirmedPickup[_assetId][rental.borrower]
        );
    }
    
    function isRentalLate(uint256 _assetId) public view assetExists(_assetId) returns (bool) {
        uint256 rentalId = activeRentalForAsset[_assetId];
        if (rentalId == 0) return false;
        
        RentalAgreement memory r = rentals[rentalId];
        return r.status == RentalStatus.Active && block.timestamp > r.endTime;
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
