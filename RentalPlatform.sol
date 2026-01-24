// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title RentalPlatform
 * @dev Comprehensive P2P rental platform for physical assets
 * @notice Handles asset registry, rental agreements, collateral, and reputation
 * 
 * CURRENT IMPLEMENTATION:
 * - Task 1: Asset Registry (COMPLETED)
 * 
 * FUTURE TASKS (Structure ready for expansion):
 * - Task 2: Rental Agreement & Handshake Mechanism
 * - Task 3: Collateral & Reputation Tracking
 * - Task 4: Payment Processing & Late Penalties
 */
contract RentalPlatform {
    
    // ============================================
    // STATE VARIABLES - ASSET REGISTRY
    // ============================================
    
    /**
     * @dev Structure to store physical asset details
     */
    struct PhysicalAsset {
        address owner;           // Wallet address of the lender
        string name;            // Item name (e.g., drill, camera)
        string description;     // Details about item's condition or use
        uint256 rentalFee;      // Price per day/duration in Wei
        uint256 safetyBond;     // Required collateral deposit
        bool isAvailable;       // Flag showing if item is currently listed for rent
    }
    
    // Mapping to store all listed assets by unique ID
    mapping(uint256 => PhysicalAsset) public assets;
    
    // Counter to track and generate IDs for new listings
    uint256 public assetCount;
    
    // Contract owner for basic maintenance
    address public contractOwner;
    
    // ============================================
    // STATE VARIABLES - RENTAL AGREEMENTS (Future Task 2)
    // ============================================
    
    // TODO: Add RentalAgreement struct
    // TODO: Add rental tracking mappings
    // TODO: Add handshake mechanism variables
    
    // ============================================
    // STATE VARIABLES - COLLATERAL & REPUTATION (Future Task 3)
    // ============================================
    
    // TODO: Add safetyBondsLocked mapping
    // TODO: Add reputationScore mapping
    // TODO: Add totalRentalsCompleted mapping
    
    // ============================================
    // CONSTANTS & SECURITY VARIABLES (Future Task 4)
    // ============================================
    
    // TODO: Add LATE_PENALTY_RATE constant
    // TODO: Add payment processing variables
    
    // ============================================
    // EVENTS - ASSET REGISTRY
    // ============================================
    
    event AssetRegistered(
        uint256 indexed assetId,
        address indexed owner,
        string name,
        uint256 rentalFee,
        uint256 safetyBond
    );
    
    event AssetUpdated(
        uint256 indexed assetId,
        uint256 rentalFee,
        uint256 safetyBond,
        bool isAvailable
    );
    
    event AssetAvailabilityChanged(
        uint256 indexed assetId,
        bool isAvailable
    );
    
    // ============================================
    // MODIFIERS
    // ============================================
    
    modifier onlyAssetOwner(uint256 _assetId) {
        require(assets[_assetId].owner == msg.sender, "Only asset owner can perform this action");
        _;
    }
    
    modifier assetExists(uint256 _assetId) {
        require(_assetId > 0 && _assetId <= assetCount, "Asset does not exist");
        _;
    }
    
    modifier validAssetDetails(string memory _name, uint256 _rentalFee, uint256 _safetyBond) {
        require(bytes(_name).length > 0, "Asset name cannot be empty");
        require(_rentalFee > 0, "Rental fee must be greater than 0");
        require(_safetyBond > 0, "Safety bond must be greater than 0");
        _;
    }
    
    modifier onlyContractOwner() {
        require(msg.sender == contractOwner, "Only contract owner can perform this action");
        _;
    }
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor() {
        contractOwner = msg.sender;
        assetCount = 0;
    }
    
    // ============================================
    // ASSET REGISTRY FUNCTIONS (Task 1 - COMPLETED)
    // ============================================
    
    /**
     * @dev Register a new physical asset for rental
     * @param _name Name of the asset (e.g., "Electric Drill", "DSLR Camera")
     * @param _description Description of the asset's condition or use
     * @param _rentalFee Rental fee per day/duration in Wei
     * @param _safetyBond Required safety bond/collateral in Wei
     * @return assetId The unique ID of the newly registered asset
     */
    function registerAsset(
        string memory _name,
        string memory _description,
        uint256 _rentalFee,
        uint256 _safetyBond
    ) 
        public 
        validAssetDetails(_name, _rentalFee, _safetyBond)
        returns (uint256) 
    {
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
    
    /**
     * @dev Update asset pricing (rental fee and safety bond)
     * @param _assetId ID of the asset to update
     * @param _rentalFee New rental fee in Wei
     * @param _safetyBond New safety bond amount in Wei
     */
    function updateAssetPricing(
        uint256 _assetId,
        uint256 _rentalFee,
        uint256 _safetyBond
    ) 
        public 
        assetExists(_assetId)
        onlyAssetOwner(_assetId)
    {
        require(_rentalFee > 0, "Rental fee must be greater than 0");
        require(_safetyBond > 0, "Safety bond must be greater than 0");
        
        assets[_assetId].rentalFee = _rentalFee;
        assets[_assetId].safetyBond = _safetyBond;
        
        emit AssetUpdated(_assetId, _rentalFee, _safetyBond, assets[_assetId].isAvailable);
    }
    
    /**
     * @dev Update asset description
     * @param _assetId ID of the asset to update
     * @param _description New description
     */
    function updateAssetDescription(
        uint256 _assetId,
        string memory _description
    ) 
        public 
        assetExists(_assetId)
        onlyAssetOwner(_assetId)
    {
        assets[_assetId].description = _description;
    }
    
    /**
     * @dev Set asset availability (list/unlist for rent)
     * @param _assetId ID of the asset
     * @param _isAvailable New availability status (true = available, false = unlisted)
     */
    function setAssetAvailability(
        uint256 _assetId,
        bool _isAvailable
    ) 
        public 
        assetExists(_assetId)
        onlyAssetOwner(_assetId)
    {
        assets[_assetId].isAvailable = _isAvailable;
        
        emit AssetAvailabilityChanged(_assetId, _isAvailable);
    }
    
    // ============================================
    // VIEW FUNCTIONS - ASSET REGISTRY
    // ============================================
    
    /**
     * @dev Get complete asset details
     * @param _assetId ID of the asset
     * @return owner Address of the asset owner
     * @return name Name of the asset
     * @return description Description of the asset
     * @return rentalFee Rental fee in Wei
     * @return safetyBond Safety bond in Wei
     * @return isAvailable Availability status
     */
    function getAsset(uint256 _assetId) 
        public 
        view 
        assetExists(_assetId)
        returns (
            address owner,
            string memory name,
            string memory description,
            uint256 rentalFee,
            uint256 safetyBond,
            bool isAvailable
        ) 
    {
        PhysicalAsset memory asset = assets[_assetId];
        return (
            asset.owner,
            asset.name,
            asset.description,
            asset.rentalFee,
            asset.safetyBond,
            asset.isAvailable
        );
    }
    
    /**
     * @dev Check if asset is available for rent
     * @param _assetId ID of the asset
     * @return Boolean indicating availability
     */
    function isAssetAvailable(uint256 _assetId) 
        public 
        view 
        assetExists(_assetId)
        returns (bool) 
    {
        return assets[_assetId].isAvailable;
    }
    
    /**
     * @dev Get total number of registered assets
     * @return Total asset count
     */
    function getTotalAssets() public view returns (uint256) {
        return assetCount;
    }
    
    /**
     * @dev Get all assets owned by a specific address
     * @param _owner Address of the owner
     * @return Array of asset IDs owned by the address
     */
    function getAssetsByOwner(address _owner) 
        public 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory tempAssets = new uint256[](assetCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= assetCount; i++) {
            if (assets[i].owner == _owner) {
                tempAssets[count] = i;
                count++;
            }
        }
        
        // Create properly sized array
        uint256[] memory ownerAssets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            ownerAssets[i] = tempAssets[i];
        }
        
        return ownerAssets;
    }
    
    /**
     * @dev Get all available assets for rent
     * @return Array of available asset IDs
     */
    function getAvailableAssets() 
        public 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory tempAssets = new uint256[](assetCount);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= assetCount; i++) {
            if (assets[i].isAvailable) {
                tempAssets[count] = i;
                count++;
            }
        }
        
        // Create properly sized array
        uint256[] memory availableAssets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            availableAssets[i] = tempAssets[i];
        }
        
        return availableAssets;
    }
    
    // ============================================
    // RENTAL AGREEMENT FUNCTIONS (Future Task 2)
    // ============================================
    
    // TODO: Add rental creation function
    // TODO: Add handshake confirmation functions
    // TODO: Add rental status management
    
    // ============================================
    // COLLATERAL & REPUTATION FUNCTIONS (Future Task 3)
    // ============================================
    
    // TODO: Add deposit safety bond function
    // TODO: Add release bond function
    // TODO: Add reputation update functions
    
    // ============================================
    // PAYMENT & PENALTY FUNCTIONS (Future Task 4)
    // ============================================
    
    // TODO: Add payment processing
    // TODO: Add late penalty calculation
    // TODO: Add fund distribution
}
