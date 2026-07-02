// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

import {ERC721H} from "./ERC-721H.sol";
import {ERC721HStorageLib} from "./ERC721HStorageLib.sol";
import {ERC721HCoreLib} from "./ERC721HCoreLib.sol";
import {IdentityRegistry} from "./IdentityRegistry.sol";

/**
 * @title CarbonCreditTokenomicsContract
 * @author Enhanced for 2026 RWA Integration
 * @notice Complete carbon credit trading system with provenance tracking and DeFi integration
 * @dev Integrates with ERC-721H for immutable provenance tracking
 */
contract CarbonCreditTokenomicsContract is 
    Initializable, 
    ERC1155Upgradeable, 
    AccessControlUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable,
    ERC165 
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    // ==========================================
    // CONSTANTS
    // ==========================================
    
    uint96 public constant BASIS_POINTS = 10000;
    uint96 public constant MAX_FEE_PERCENT = 1000; // 10%
    uint96 public constant MAX_REWARD_PERCENT = 1500; // 15%
    uint128 public constant MAX_STAKE_AMOUNT = 1000000 * 1e18;
    uint128 public constant MAX_STAKE_DURATION = 365 days;
    uint128 public constant MINIMUM_STAKE_DURATION = 1 days;
    uint256 public constant MAX_BULK_ROLE_ASSIGNMENTS = 50;
    uint256 public constant MAX_OPERATIONS_PER_BLOCK = 5;
    uint256 public constant PROPOSAL_EXPIRY_TIME = 7 days;
    uint256 public constant STAKING_REWARD_RATE = 10; // 10% APY

    // ==========================================
    // ROLES
    // ==========================================
    
    bytes32 public constant ROLE_ADMIN = DEFAULT_ADMIN_ROLE;
    bytes32 public constant ROLE_VALIDATOR = keccak256("ROLE_VALIDATOR");
    bytes32 public constant ROLE_MINTER = keccak256("ROLE_MINTER");
    bytes32 public constant ROLE_FRACTIONALIZER = keccak256("ROLE_FRACTIONALIZER");
    bytes32 public constant ROLE_BURNER = keccak256("ROLE_BURNER");
    bytes32 public constant ROLE_PAUSER = keccak256("ROLE_PAUSER");
    bytes32 public constant ROLE_VERIFIER = keccak256("ROLE_VERIFIER");

    // ==========================================
    // STORAGE
    // ==========================================
    
    // Carbon credit data
    mapping(uint256 => CarbonCreditData) public carbonCreditData;
    mapping(uint256 => string) private _tokenURIs;
    
    // Staking
    mapping(address => mapping(uint256 => Stake)) public stakes;
    mapping(address => uint256) public stakingRewards;
    mapping(address => uint256) public lastStakeUpdate;
    
    // Slashing
    mapping(uint256 => SlashProposal) public slashProposals;
    CountersUpgradeable.Counter private _proposalCounter;
    
    // Configuration
    address public treasury;
    uint256 public transferFeePercent;
    uint256 public stakingRewardPercent;
    uint256 public slashApprovalThreshold;
    uint256 public totalSupply;
    uint256 public totalStaked;
    
    // Timelocks
    mapping(bytes32 => uint256) public timeLocks;
    mapping(address => uint256) public lastOperationBlock;
    mapping(bytes32 => bool) public circuitBreakers;
    
    // Compliance Integration
    address public identityRegistry;
    address public provenanceNFT; // ERC-721H contract
    mapping(uint256 => uint256) public provenanceTokenId; // Map carbon credit -> provenance NFT
    
    // ==========================================
    // STRUCTS
    // ==========================================
    
    struct Stake {
        uint128 amount;
        uint64 startTime;
        uint64 lastClaimTime;
        bool isActive;
        uint256 rewardDebt;
    }

    struct CarbonCreditData {
        uint128 totalAmount;
        uint128 fractionalizedAmount;
        uint64 issuanceDate;
        uint64 verificationDate;
        bool isValidated;
        bool isVerified;
        string projectName;
        string projectCountry;
        string hydrogenProductionMethod;
        string energySource;
        uint64 carbonCaptureEfficiency;
        uint256 carbonFootprintReduction; // In tons CO2
        bytes32 legalAttestationHash; // IPFS hash of legal docs
    }

    struct SlashProposal {
        address staker;
        uint256 tokenId;
        uint256 slashAmount;
        uint256 proposedAt;
        uint256 validatorApprovals;
        mapping(address => bool) hasApproved;
        bool isExecuted;
        bool isCancelled;
    }

    // ==========================================
    // EVENTS
    // ==========================================
    
    event CarbonCreditMinted(uint256 indexed tokenId, address indexed recipient, uint256 amount, string metadataURI);
    event CarbonCreditFractionalized(uint256 indexed tokenId, uint256 amount, uint256 fractions, address indexed fractionalizer);
    event CarbonCreditStaked(address indexed staker, uint256 indexed tokenId, uint256 amount);
    event CarbonCreditUnstaked(address indexed staker, uint256 indexed tokenId, uint256 amount, uint256 reward);
    event CarbonCreditVerified(uint256 indexed tokenId, address indexed verifier, bool status);
    event StakeSlashed(address indexed staker, uint256 indexed tokenId, uint256 slashAmount);
    event SlashProposed(uint256 indexed proposalId, address indexed staker, uint256 indexed tokenId, uint256 amount);
    event SlashApproved(uint256 indexed proposalId, address indexed validator);
    event SlashExecuted(uint256 indexed proposalId, address indexed staker, uint256 indexed tokenId, uint256 slashAmount);
    event SlashCancelled(uint256 indexed proposalId, address indexed canceller);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TransferFeeUpdated(uint256 newFeePercent);
    event StakingRewardUpdated(uint256 newRewardPercent);
    event IdentityRegistrySet(address indexed registry);
    event ProvenanceSet(address indexed provenanceNFT);

    // ==========================================
    // ERRORS
    // ==========================================
    
    error InsufficientTokensForFractionalization();
    error FractionalizationAmountExceedsTotal();
    error ZeroFractionsNotAllowed();
    error InvalidStakeDuration();
    error InvalidStakeAmount();
    error NoActiveStake();
    error InsufficientStakedBalance();
    error ProposalExpired();
    error ProposalAlreadyExecuted();
    error ProposalNotApproved();
    error ComplianceCheckFailed();
    error NotCompliant();
    error InvalidTokenId();

    // ==========================================
    // INITIALIZER
    // ==========================================
    
    function initialize(
        string memory baseURI,
        address _treasury,
        address[] memory validators,
        address[] memory minters,
        address _identityRegistry,
        address _provenanceNFT,
        uint256 _slashApprovalThreshold
    ) public initializer {
        require(_treasury != address(0), "Zero treasury");
        require(_slashApprovalThreshold > 0, "Invalid threshold");
        require(_identityRegistry != address(0), "Zero identity registry");
        require(_provenanceNFT != address(0), "Zero provenance NFT");

        __ERC1155_init(baseURI);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(ROLE_ADMIN, _msgSender());
        _grantRole(ROLE_FRACTIONALIZER, _msgSender());
        _grantRole(ROLE_BURNER, _msgSender());
        _grantRole(ROLE_PAUSER, _msgSender());

        // Batch grant roles with validation
        uint256 validatorCount = validators.length > MAX_BULK_ROLE_ASSIGNMENTS ? 
            MAX_BULK_ROLE_ASSIGNMENTS : validators.length;
        for (uint i = 0; i < validatorCount; i++) {
            require(validators[i] != address(0), "Zero validator address");
            _grantRole(ROLE_VALIDATOR, validators[i]);
        }

        uint256 minterCount = minters.length > MAX_BULK_ROLE_ASSIGNMENTS ?
            MAX_BULK_ROLE_ASSIGNMENTS : minters.length;
        for (uint i = 0; i < minterCount; i++) {
            require(minters[i] != address(0), "Zero minter address");
            _grantRole(ROLE_MINTER, minters[i]);
        }

        treasury = _treasury;
        identityRegistry = _identityRegistry;
        provenanceNFT = _provenanceNFT;
        transferFeePercent = 500; // 5%
        stakingRewardPercent = 1000; // 10%
        slashApprovalThreshold = _slashApprovalThreshold;
        
        // Set timelock for critical operations
        _setTimelock(keccak256("UPDATE_TREASURY"), 2 days);
        _setTimelock(keccak256("UPDATE_FEE"), 1 days);
        _setTimelock(keccak256("UPGRADE"), 7 days);
    }

    // ==========================================
    // COMPLIANCE INTEGRATION
    // ==========================================
    
    function setIdentityRegistry(address _registry) external onlyRole(ROLE_ADMIN) {
        require(_registry != address(0), "Zero address");
        identityRegistry = _registry;
        emit IdentityRegistrySet(_registry);
    }

    function setProvenanceNFT(address _provenance) external onlyRole(ROLE_ADMIN) {
        require(_provenance != address(0), "Zero address");
        provenanceNFT = _provenance;
        emit ProvenanceSet(_provenance);
    }

    /// @notice Link carbon credit to provenance NFT
    function linkProvenance(uint256 tokenId, uint256 provenanceTokenId) 
        external 
        onlyRole(ROLE_ADMIN) 
    {
        require(provenanceNFT != address(0), "Provenance NFT not set");
        require(carbonCreditData[tokenId].totalAmount > 0, "Token doesn't exist");
        
        provenanceTokenId[tokenId] = provenanceTokenId;
        emit ProvenanceLinked(tokenId, provenanceTokenId);
    }

    event ProvenanceLinked(uint256 indexed tokenId, uint256 indexed provenanceTokenId);

    // ==========================================
    // CORE FUNCTIONS
    // ==========================================
    
    /// @notice Mint carbon credits with compliance check
    function mintCarbonCredit(
        address to,
        uint256 amount,
        string memory metadataURI,
        CarbonCreditData memory data
    ) external onlyRole(ROLE_MINTER) nonReentrant whenNotPaused {
        require(to != address(0), "Zero address");
        require(amount > 0, "Zero amount");
        require(IdentityRegistry(identityRegistry).isVerified(to), "Recipient not KYC verified");
        
        uint256 tokenId = _nextTokenId();
        _nextTokenId.increment();
        
        carbonCreditData[tokenId] = data;
        carbonCreditData[tokenId].totalAmount = uint128(amount);
        carbonCreditData[tokenId].issuanceDate = uint64(block.timestamp);
        _tokenURIs[tokenId] = metadataURI;
        
        _mint(to, tokenId, amount, "");
        totalSupply += amount;
        
        emit CarbonCreditMinted(tokenId, to, amount, metadataURI);
    }

    /// @notice Batch mint with compliance
    function batchMintCarbonCredit(
        address[] memory tos,
        uint256[] memory amounts,
        string[] memory metadataURIs,
        CarbonCreditData[] memory datas
    ) external onlyRole(ROLE_MINTER) nonReentrant whenNotPaused {
        require(tos.length == amounts.length && amounts.length == metadataURIs.length, "Length mismatch");
        require(tos.length <= MAX_BULK_ROLE_ASSIGNMENTS, "Batch too large");
        
        for (uint i = 0; i < tos.length; i++) {
            require(IdentityRegistry(identityRegistry).isVerified(tos[i]), "Recipient not verified");
            uint256 tokenId = _nextTokenId();
            _nextTokenId.increment();
            
            carbonCreditData[tokenId] = datas[i];
            carbonCreditData[tokenId].totalAmount = uint128(amounts[i]);
            carbonCreditData[tokenId].issuanceDate = uint64(block.timestamp);
            _tokenURIs[tokenId] = metadataURIs[i];
            
            _mint(tos[i], tokenId, amounts[i], "");
            totalSupply += amounts[i];
            
            emit CarbonCreditMinted(tokenId, tos[i], amounts[i], metadataURIs[i]);
        }
    }

    // ==========================================
    // STAKING WITH REWARDS
    // ==========================================
    
    /// @notice Stake carbon credits with automatic reward calculation
    function stake(uint256 tokenId, uint128 amount, uint64 duration) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(amount > 0 && amount <= MAX_STAKE_AMOUNT, "Invalid amount");
        require(duration >= MINIMUM_STAKE_DURATION && duration <= MAX_STAKE_DURATION, "Invalid duration");
        
        // Transfer tokens to contract
        safeTransferFrom(_msgSender(), address(this), tokenId, amount, "");
        
        // Update stake
        Stake storage stakeInfo = stakes[_msgSender()][tokenId];
        _updateRewards(_msgSender(), tokenId);
        
        if (stakeInfo.isActive) {
            stakeInfo.amount += amount;
        } else {
            stakes[_msgSender()][tokenId] = Stake({
                amount: amount,
                startTime: uint64(block.timestamp),
                lastClaimTime: uint64(block.timestamp),
                isActive: true,
                rewardDebt: 0
            });
        }
        
        totalStaked += amount;
        emit CarbonCreditStaked(_msgSender(), tokenId, amount);
    }

    /// @notice Unstake with accumulated rewards
    function unstake(uint256 tokenId, uint128 amount) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        Stake storage stakeInfo = stakes[_msgSender()][tokenId];
        require(stakeInfo.isActive, "No active stake");
        require(stakeInfo.amount >= amount, "Insufficient staked");
        
        // Calculate rewards
        _updateRewards(_msgSender(), tokenId);
        uint256 reward = _calculateReward(_msgSender(), tokenId);
        
        if (reward > 0) {
            _mint(_msgSender(), tokenId, reward, "");
            stakingRewards[_msgSender()] = 0;
            emit CarbonCreditUnstaked(_msgSender(), tokenId, amount, reward);
        }
        
        // Update stake
        stakeInfo.amount -= amount;
        if (stakeInfo.amount == 0) {
            stakeInfo.isActive = false;
        }
        
        // Return staked tokens
        _safeTransfer(address(this), _msgSender(), tokenId, amount, "");
        totalStaked -= amount;
        
        emit CarbonCreditUnstaked(_msgSender(), tokenId, amount, reward);
    }

    /// @notice Claim rewards without unstaking
    function claimRewards(uint256 tokenId) external nonReentrant whenNotPaused {
        Stake storage stakeInfo = stakes[_msgSender()][tokenId];
        require(stakeInfo.isActive, "No active stake");
        
        _updateRewards(_msgSender(), tokenId);
        uint256 reward = stakingRewards[_msgSender()];
        
        if (reward > 0) {
            _mint(_msgSender(), tokenId, reward, "");
            stakingRewards[_msgSender()] = 0;
            emit RewardsClaimed(_msgSender(), tokenId, reward);
        }
    }

    event RewardsClaimed(address indexed staker, uint256 indexed tokenId, uint256 reward);

    // ==========================================
    // REWARD CALCULATIONS
    // ==========================================
    
    function _updateRewards(address staker, uint256 tokenId) internal {
        Stake storage stakeInfo = stakes[staker][tokenId];
        if (!stakeInfo.isActive) return;
        
        uint256 reward = _calculateReward(staker, tokenId);
        stakingRewards[staker] += reward;
        stakeInfo.lastClaimTime = uint64(block.timestamp);
    }

    function _calculateReward(address staker, uint256 tokenId) internal view returns (uint256) {
        Stake storage stakeInfo = stakes[staker][tokenId];
        if (!stakeInfo.isActive || stakeInfo.amount == 0) return 0;
        
        uint256 stakingDuration = block.timestamp - stakeInfo.lastClaimTime;
        if (stakingDuration == 0) return 0;
        
        // Simple APY calculation
        uint256 reward = (stakeInfo.amount * stakingDuration * STAKING_REWARD_RATE) / (365 days * 100);
        return reward;
    }

    // ==========================================
    // SLASHING WITH GOVERNANCE
    // ==========================================
    
    /// @notice Propose slashing a validator's stake
    function proposeSlash(uint256 tokenId, address staker, uint256 amount) 
        external 
        onlyRole(ROLE_VALIDATOR) 
        whenNotPaused 
        nonReentrant 
    {
        require(carbonCreditData[tokenId].totalAmount > 0, "Token doesn't exist");
        require(stakes[staker][tokenId].isActive, "No active stake");
        require(stakes[staker][tokenId].amount >= amount, "Amount exceeds staked");
        require(amount > 0, "Zero slash amount");
        
        uint256 proposalId = _proposalCounter.current();
        SlashProposal storage proposal = slashProposals[proposalId];
        proposal.staker = staker;
        proposal.tokenId = tokenId;
        proposal.slashAmount = amount;
        proposal.proposedAt = block.timestamp;
        proposal.isExecuted = false;
        proposal.isCancelled = false;
        
        emit SlashProposed(proposalId, staker, tokenId, amount);
        _proposalCounter.increment();
    }

    /// @notice Approve a slash proposal
    function approveSlash(uint256 proposalId) 
        external 
        onlyRole(ROLE_VALIDATOR) 
        whenNotPaused 
    {
        SlashProposal storage proposal = slashProposals[proposalId];
        require(proposal.staker != address(0), "Proposal doesn't exist");
        require(!proposal.isExecuted, "Already executed");
        require(!proposal.isCancelled, "Cancelled");
        require(block.timestamp <= proposal.proposedAt + PROPOSAL_EXPIRY_TIME, "Expired");
        require(!proposal.hasApproved[_msgSender()], "Already approved");
        
        proposal.hasApproved[_msgSender()] = true;
        proposal.validatorApprovals++;
        
        emit SlashApproved(proposalId, _msgSender());
    }

    /// @notice Execute slash proposal after threshold reached
    function executeSlash(uint256 proposalId) 
        external 
        onlyRole(ROLE_ADMIN) 
        whenNotPaused 
        nonReentrant 
    {
        SlashProposal storage proposal = slashProposals[proposalId];
        require(proposal.staker != address(0), "Proposal doesn't exist");
        require(!proposal.isExecuted, "Already executed");
        require(!proposal.isCancelled, "Cancelled");
        require(block.timestamp <= proposal.proposedAt + PROPOSAL_EXPIRY_TIME, "Expired");
        require(proposal.validatorApprovals >= slashApprovalThreshold, "Not enough approvals");
        
        // Execute slash
        Stake storage stakeInfo = stakes[proposal.staker][proposal.tokenId];
        require(stakeInfo.isActive, "No active stake");
        require(stakeInfo.amount >= proposal.slashAmount, "Insufficient balance");
        
        stakeInfo.amount -= uint128(proposal.slashAmount);
        if (stakeInfo.amount == 0) {
            stakeInfo.isActive = false;
        }
        
        // Burn slashed tokens
        _burn(address(this), proposal.tokenId, proposal.slashAmount);
        totalSupply -= proposal.slashAmount;
        totalStaked -= proposal.slashAmount;
        
        proposal.isExecuted = true;
        
        emit SlashExecuted(proposalId, proposal.staker, proposal.tokenId, proposal.slashAmount);
        emit StakeSlashed(proposal.staker, proposal.tokenId, proposal.slashAmount);
    }

    // ==========================================
    // FRACTIONALIZATION
    // ==========================================
    
    function fractionalize(
        uint256 tokenId,
        uint256 amount,
        uint256 fractions
    ) external onlyRole(ROLE_FRACTIONALIZER) nonReentrant {
        require(tokenId > 0, "Invalid token ID");
        require(amount > 0, "Invalid amount");
        require(fractions > 0, "Fractions cannot be zero");
        require(carbonCreditData[tokenId].totalAmount >= amount, "Not enough tokens");
        
        carbonCreditData[tokenId].fractionalizedAmount += uint128(amount);
        carbonCreditData[tokenId].totalAmount -= uint128(amount);
        
        emit CarbonCreditFractionalized(tokenId, amount, fractions, _msgSender());
    }

    // ==========================================
    // ADMIN FUNCTIONS
    // ==========================================
    
    function updateTreasury(address newTreasury) 
        external 
        onlyRole(ROLE_ADMIN) 
        withTimelock(keccak256("UPDATE_TREASURY")) 
    {
        require(newTreasury != address(0), "Zero address");
        require(newTreasury != treasury, "Same address");
        
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function updateTransferFee(uint256 newFee) 
        external 
        onlyRole(ROLE_ADMIN) 
        withTimelock(keccak256("UPDATE_FEE")) 
    {
        require(newFee <= MAX_FEE_PERCENT, "Fee too high");
        transferFeePercent = newFee;
        emit TransferFeeUpdated(newFee);
    }

    function updateStakingReward(uint256 newReward) 
        external 
        onlyRole(ROLE_ADMIN) 
    {
        require(newReward <= MAX_REWARD_PERCENT, "Reward too high");
        stakingRewardPercent = newReward;
        emit StakingRewardUpdated(newReward);
    }

    function updateURI(uint256 tokenId, string memory newURI) 
        external 
        onlyRole(ROLE_ADMIN) 
    {
        require(carbonCreditData[tokenId].totalAmount > 0, "Token doesn't exist");
        _tokenURIs[tokenId] = newURI;
        emit MetadataUpdated(tokenId, newURI);
    }

    function validateCredit(uint256 tokenId) external onlyRole(ROLE_VERIFIER) {
        require(carbonCreditData[tokenId].totalAmount > 0, "Token doesn't exist");
        carbonCreditData[tokenId].isValidated = true;
        carbonCreditData[tokenId].verificationDate = uint64(block.timestamp);
        emit ValidationStatusChanged(tokenId, true);
    }

    function verifyCredit(uint256 tokenId) external onlyRole(ROLE_VERIFIER) {
        require(carbonCreditData[tokenId].totalAmount > 0, "Token doesn't exist");
        carbonCreditData[tokenId].isVerified = true;
        emit CarbonCreditVerified(tokenId, _msgSender(), true);
    }

    // ==========================================
    // TIMELOCK MECHANISM
    // ==========================================
    
    modifier withTimelock(bytes32 action) {
        uint256 lockTime = timeLocks[action];
        require(block.timestamp >= lockTime, "Timelock active");
        _;
    }

    function _setTimelock(bytes32 action, uint256 duration) internal {
        timeLocks[action] = block.timestamp + duration;
    }

    // ==========================================
    // VIEW FUNCTIONS
    // ==========================================
    
    function uri(uint256 tokenId) public view override returns (string memory) {
        require(carbonCreditData[tokenId].totalAmount > 0, "Token doesn't exist");
        string memory tokenURI = _tokenURIs[tokenId];
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        return super.uri(tokenId);
    }

    function getStakingInfo(address staker, uint256 tokenId) 
        external 
        view 
        returns (
            uint256 amount,
            uint256 startTime,
            uint256 lastClaim,
            bool isActive,
            uint256 pendingReward
        ) 
    {
        Stake storage stakeInfo = stakes[staker][tokenId];
        return (
            stakeInfo.amount,
            stakeInfo.startTime,
            stakeInfo.lastClaimTime,
            stakeInfo.isActive,
            _calculateReward(staker, tokenId) + stakingRewards[staker]
        );
    }

    function getCarbonCreditData(uint256 tokenId) 
        external 
        view 
        returns (
            uint256 total,
            uint256 fractionalized,
            uint256 issuance,
            bool isValidated,
            bool isVerified,
            string memory projectName,
            string memory country,
            string memory productionMethod,
            uint256 efficiency
        ) 
    {
        CarbonCreditData storage data = carbonCreditData[tokenId];
        return (
            data.totalAmount,
            data.fractionalizedAmount,
            data.issuanceDate,
            data.isValidated,
            data.isVerified,
            data.projectName,
            data.projectCountry,
            data.hydrogenProductionMethod,
            data.carbonCaptureEfficiency
        );
    }

    // ==========================================
    // OVERRIDES
    // ==========================================
    
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        
        // Compliance check for transfers
        if (from != address(0) && to != address(0)) {
            require(IdentityRegistry(identityRegistry).isVerified(to), "Recipient not verified");
        }
    }

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(ROLE_ADMIN) 
        withTimelock(keccak256("UPGRADE"))
    {}

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC1155Upgradeable, AccessControlUpgradeable, ERC165) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

    // ==========================================
    // EMERGENCY FUNCTIONS
    // ==========================================
    
    function emergencyWithdraw(uint256 tokenId) external nonReentrant {
        require(paused(), "Only when paused");
        
        Stake storage stakeInfo = stakes[msg.sender][tokenId];
        require(stakeInfo.isActive, "No active stake");
        
        uint256 amount = stakeInfo.amount;
        stakeInfo.amount = 0;
        stakeInfo.isActive = false;
        totalStaked -= amount;
        
        _safeTransfer(address(this), msg.sender, tokenId, amount, "");
        
        emit CarbonCreditUnstaked(msg.sender, tokenId, amount, 0);
    }

    // ==========================================
    // RECOVERY FUNCTIONS
    // ==========================================
    
    function recoverERC20(address token, address to, uint256 amount) 
        external 
        onlyRole(ROLE_ADMIN) 
    {
        require(to != address(0), "Zero address");
        IERC20(token).safeTransfer(to, amount);
        emit TokenRecovered(token, to, amount);
    }

    event MetadataUpdated(uint256 indexed tokenId, string newURI);
    event ValidationStatusChanged(uint256 indexed tokenId, bool status);
    event TokenRecovered(address indexed token, address indexed to, uint256 amount);
    event ProvenanceLinked(uint256 indexed tokenId, uint256 indexed provenanceTokenId);
    event CarbonCreditVerified(uint256 indexed tokenId, address indexed verifier, bool status);
}

// ==========================================
// COUNTERS (Missing from original)
// ==========================================

library Counters {
    struct Counter {
        uint256 _value;
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }
}