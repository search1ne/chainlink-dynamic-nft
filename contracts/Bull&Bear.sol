// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract BullBear is 
    ERC721, 
    ERC721Enumerable, 
    ERC721URIStorage, 
    Ownable, 
    KeeperCompatibleInterface,
    VRFConsumerBaseV2
{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    AggregatorV3Interface public priceFeed;
    VRFCoordinatorV2Interface public COORDINATOR;
    
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint32 public callbackGasLimit = 1000000; // set higher as fullfillRandomWords is doing a LOT of heavy lifting.
    uint64 public s_subscriptionId;
    bytes32 keyhash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15; // keyhash for Goerli

    /* Use an interval in seconds and timestamp to slow execution of Upkeep */
    uint256 public interval;
    uint256 public lastTimeStamp;

    int256 public currentPrice;

    enum MarketTrend{ BULL, BEAR }
    MarketTrend public currentMarketTrend = MarketTrend.BULL;

    /* 
     * IPFS URIs for the dynamic nft graphics/metadata.
     * NOTE: These connect to my IPFS Companion node.
     * You should upload the contents of the /ipfs folder to your own node for development.
     */
    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmS1v9jRYvgikKQD6RrssSKiBTBH3szDK6wzRWF4QBvunR?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRsTqwTXXkV8rFAT4XsNPDkdZs5WxUx9E5KwFaVfYWjMv?filename=party_bull.json",
        "https://ipfs.io/ipfs/Qmc3ueexsATjqwpSVJNxmdf2hStWuhSByHtHK5fyJ3R2xb?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/QmQMqVUHjCAxeFNE9eUxf89H1b7LpdzhvQZ8TXnj4FPuX1?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmP2v34MVdoxLSFj1LbGW261fvLcoAsnJWHaBK238hWnHJ?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmZVfjuDiUfvxPM7qAvq8Umk3eHyVh7YTbFon973srwFMD?filename=simple_bear.json"
    ];

    event TokensUpdated(string marketTrend);


    constructor(uint256 updateInterval, address _priceFeed, address _vrfCoordinator) 
        ERC721("Bull&Bear", "BBTK")
        VRFConsumerBaseV2(_vrfCoordinator)
    {
        /* Set Keeper update interval */
        interval = updateInterval;
        lastTimeStamp = block.timestamp;

        priceFeed = AggregatorV3Interface(_priceFeed);
        /* set the price for the chosen currency pair */
        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    function safeMint(address to) 
        public 
        onlyOwner 
    {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);

        /* Defaults to gamer bull NFT on mint */
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);
    }

    function checkUpkeep(bytes calldata /*checkData*/) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory /*performData*/) 
    {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    /* Modified to handle VRF */
    function performUpkeep(bytes calldata /*performData*/) 
        external 
        override 
    {
        /* Highly recommended revalidating the upkeep in the performUpkeep function */
        if ((block.timestamp - lastTimeStamp) > interval) 
        {
            lastTimeStamp = block.timestamp;
            int256 latestPrice = getLatestPrice();

            if (latestPrice == currentPrice) 
            {   
                return;
            }

            if (latestPrice < currentPrice) 
            {   
                /* updateAllTokenUris("bear"); */
                currentMarketTrend = MarketTrend.BEAR;
            } 

            else 
            {
                /* updateAllTokenUris("bull"); */
                currentMarketTrend = MarketTrend.BULL;
            }

            /* Initiate the VRF calls to get a random number (word) that will then be used to choose on the of URIs
             * that gets applied to all minted tokens.
             */
            requestRandomnessForNFTUris();
            /* Update currentPrice */
            currentPrice = latestPrice;
        }
    }

    function getLatestPrice() 
        public 
        view 
        returns (int256) 
    {
        (
            /*uint80 roundID*/,
            int256 price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        
        return price;   // example price returned 111296000000
    }

    function requestRandomnessForNFTUris()
        internal
    {
        require(s_subscriptionId != 0, "Subscription ID not set");

        /* Will revert if subscription is not set and funded */
        s_requestId = COORDINATOR.requestRandomWords
        (
            keyhash,
            s_subscriptionId, // See https://vrf.chain.link/
            3, // minimum confirmations before response
            callbackGasLimit,
            1 // 'numWords' : number of random values we want.
        );
        // requestId looks like uint256: 80023009725525451140349768621743705773526822376835636211719588211198618496446
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords)
        internal
        override
    {
        s_randomWords = randomWords;
        // randomWords looks like this uint256: 68187645017388103597074813724954069904348581739269924188458647203960383435815

        string[] memory urisForTrend = currentMarketTrend == MarketTrend.BULL 
            ? bullUrisIpfs 
            : bearUrisIpfs;

        uint256 idx = randomWords[0] % urisForTrend.length; // use modulo to choose a random index.

            for (uint i = 0; i < _tokenIdCounter.current(); i++) 
            {
                _setTokenURI(i, urisForTrend[idx]);
            }

        string memory trend = currentMarketTrend == MarketTrend.BULL 
            ? "bullish" 
            : "bearish";

        emit TokensUpdated(trend);
    }

        

    /* Called by performUpkeep to update nft using MockPriceFeed.sol /*
    function updateAllTokenUris(string memory trend) 
        internal 
    {
        if (compareStrings("bear", trend)) {
            for (uint i = 0; i < _tokenIdCounter.current(); i++) {
                _setTokenURI(i, bearUrisIpfs[0]);
            }
        } else {
            for (uint i = 0; i < _tokenIdCounter.current(); i++) {
                _setTokenURI(i, bullUrisIpfs[0]);
            }
        }

        emit TokensUpdated(trend);
    }

    */

    /* Start with 60. Raise to 500 after registering to Chainlink Automation to save LINK */
    function setInterval(uint256 newInterval) 
        public 
        onlyOwner 
    {
        interval = newInterval;
    }

    /* MockPriceFeed or Live Price Feed
     * Goerli ETH/USD price feed contract: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
     */
    function setPriceFeed(address newFeed) 
        public 
        onlyOwner 
    {
        priceFeed = AggregatorV3Interface(newFeed);
    }


    // For VRF Subscription Manager on https://vrf.chain.link 
    function setSubscriptionId(uint64 _id)
        public
        onlyOwner
    {
        s_subscriptionId = _id;
    }

    function setCallbackGasLimit(uint32 maxGas)
        public
        onlyOwner
    {
        callbackGasLimit = maxGas;
    }

    /* Goerli VRF Coordinator: 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D 
     * Confirm contract address by calling COORDINATOR
     */
    function setVRFCoordinator(address _address)
        public
        onlyOwner
    {
        COORDINATOR = VRFCoordinatorV2Interface(_address);
    }



    // Helpers
    /*
    function compareStrings(string memory a, string memory b) 
        internal 
        pure 
        returns (bool) 
    {   
        /* No longer used as not being called when using VRF, as we're not using enums. 
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    function updateAllTokenUris(string memory trend)
        internal
    {
        /* The logic from this has been moved up to fulfill random words. 
    }
    */


    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
