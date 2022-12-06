// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "contracts/Ownable.sol";
// owner can set the metadata
// owner can authorize set the name
// owner can duplicate
// anyone can set their primary name
// owner can set the name of a smart contract if they are the owner of the smart contract
// transfer a token to a domain evenly to all owners of the token
// get the addresses of all owners of the token
// set primary token
// set 1 month renewal time
// create subdomains

contract PFNNameService is Ownable, ERC1155 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    address public paymentToken;

    mapping(address => uint256) private primaryDomain;
    mapping(uint256 => address) private primaryDomainUser;
    mapping(address => bool) private primaryDomainType;
    mapping(uint256 => uint256) public domainCost;

    mapping(address => uint256) subDomainIndex;

    uint256 public baseCost;
    uint256 public subDomainCost;
    uint256 public contractCost;
    uint256 public expirationLength;

    mapping(bytes => uint256) public domainTokenId;

    mapping(uint256 => domainInformation) public domainInfo;

    struct domainInformation {
        uint256 expirationDate;
        uint256 graceDate;
        uint128 numberOfCreatedSubdomains;
        uint128 numberOfActiveSubdomains;
        bytes domainName;
        address owner;
        mapping(address => bool) authorizedSubdomainUsers;
        mapping(uint256 => bytes) subDomains;
    }

    constructor() ERC1155("https://game.example/api/item/{id}.json") {
        expirationLength = 31536000;
        contractCost = 5e18;
        baseCost = 5e17;
        subDomainCost = 5e17;
        domainCost[1] = 10e18;
        domainCost[2] = 10e18;
        domainCost[3] = 5e18;
        domainCost[4] = 3e18;
        domainCost[5] - 1e18;
    }

    function createDomain(string memory _domainName, uint256 _months) external {
        bytes memory _domain = bytes(_domainName);
        require(_domain.length > 0, "PFNNameSerivce: Length too small");

        uint256 oldId = domainTokenId[_domain];

        if (oldId != 0) {
            domainInformation storage dOld = domainInfo[oldId];
            if (dOld.owner != address(0)) {
                require(block.timestamp > dOld.graceDate, "PFNNameSerivce: Cannot claim used domain before grace period");
            }
            if (dOld.owner == msg.sender) {
                extendDomain(oldId, _months);
                return;
            }
            if (balanceOf(dOld.owner, oldId) > 0)
                _burn(dOld.owner, oldId, balanceOf(dOld.owner, oldId));
            primaryDomain[dOld.owner] = 0;
        }



        _tokenIds.increment();
        uint256 itemId = _tokenIds.current();

        uint256 _cost = (calculateDomainCost(_domainName) / 12) * _months;
        // IERC20(paymentToken).transferFrom(msg.sender, address(this), _cost);

        domainTokenId[_domain] = itemId;

        domainInformation storage d = domainInfo[itemId];
        d.expirationDate = block.timestamp + (_months * (30 days));
        d.graceDate = d.expirationDate + (30 days);
        d.numberOfCreatedSubdomains = 0;
        d.numberOfActiveSubdomains = 0;
        d.domainName = _domain;
        d.owner = msg.sender;

        _mint(msg.sender, itemId, 1, _domain);
    }

    function createSubDomain(uint256 itemId, string memory _subDomainName) external {
        domainInformation storage d = domainInfo[itemId];
        require(block.timestamp < d.expirationDate, "PFNNameService: Domain expired");
        require(msg.sender == d.owner || d.authorizedSubdomainUsers[msg.sender], "PFNNameService: User is not authorized");
        bytes memory _subDomain = bytes(_subDomainName);
        require(_subDomain.length > 0, "PFNNameSerivce: Length too small");
        d.subDomains[d.numberOfCreatedSubdomains] = _subDomain;
        d.numberOfCreatedSubdomains++;
        d.numberOfActiveSubdomains++;

        uint256 _cost = subDomainCost * (d.expirationDate - block.timestamp) / (30 days);
        // IERC20(paymentToken).transferFrom(msg.sender, address(this), _cost);

    }

    function removeSubDomain(uint256 itemId, uint256 subDomainId) external {
        domainInformation storage d = domainInfo[itemId];
        require(msg.sender == d.owner || d.authorizedSubdomainUsers[msg.sender], "PFNNameService: User is not authorized");
        require(keccak256(d.subDomains[subDomainId]) != keccak256(""), "PFNNameService: Invalid subdomain ID");

        d.numberOfActiveSubdomains--;
        d.subDomains[subDomainId] = "";

        // create credit system for removing subdomain
    }

    function calculateDomainCost(string memory _domainName) public view returns (uint256) {
        uint256 _cost = domainCost[bytes(_domainName).length];
        if (_cost == 0)
            return baseCost;
        return _cost;
    }

    function extendDomain(uint256 itemId, uint256 _months) public {
        domainInformation storage d = domainInfo[itemId];
        require(d.domainName.length > 0, "PFNNameSerivce: Length too small");
        require(keccak256(d.domainName) != keccak256(""), "PFNNameService: Invalid domain");
        uint256 _cost = (calculateDomainCost(string(d.domainName)) / 12) * _months + (subDomainCost * d.numberOfActiveSubdomains);
        // IERC20(paymentToken).transferFrom(msg.sender, address(this), _cost);

        d.expirationDate = d.expirationDate + (_months * 2592000);
    }

    function setPrimaryAsDomain(uint256 itemId) external {
        domainInformation storage d = domainInfo[itemId];
        require(balanceOf(msg.sender, itemId) > 0, "PFNNameService: User does not own token");

        address currentUser = primaryDomainUser[itemId];
        if (currentUser != address(0))
            primaryDomain[currentUser] = 0;

        primaryDomainType[msg.sender] = false;

        primaryDomain[msg.sender] = itemId;
        primaryDomainUser[itemId] = msg.sender;
    }

    function setPrimaryAsSubdomain(uint256 itemId, uint256 domainIndex) external {
        domainInformation storage d = domainInfo[itemId];
        require(d.owner == msg.sender || d.authorizedSubdomainUsers[msg.sender], "PFNNameService: User not authorized");
        require(keccak256(d.subDomains[domainIndex]) != keccak256(""), "PFNNameService: Invalid domain");
        primaryDomainType[msg.sender] = true;
        primaryDomain[msg.sender] = itemId;
        subDomainIndex[msg.sender] = domainIndex;
    }

    function setContractDomain(address _contract, string memory _domainName) external {
        bytes memory _domain = bytes(_domainName);
        require(Ownable(_contract).owner() == msg.sender, "PFNNameService: User is not the owner");
        uint256 _tokenId = domainTokenId[_domain];
        require(primaryDomainUser[_tokenId] == address(0), "PFNNameService: Domain already used");
        require(balanceOf(msg.sender, _tokenId) > 0);
        primaryDomain[_contract] = _tokenId;
        primaryDomainUser[_tokenId] = _contract;
    }

    function domain(address user) public view returns (string memory _domain) {
        bool _type = primaryDomainType[user];
        domainInformation storage d = domainInfo[primaryDomain[user]];
        _domain = string.concat(string(d.domainName), ".pfn");
        if (_type) {
            string memory sub = string.concat(string(d.subDomains[subDomainIndex[msg.sender]]), ".");
            _domain = string.concat(sub, _domain);
        }
    }
}
