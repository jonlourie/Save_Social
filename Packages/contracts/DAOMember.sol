// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
 
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
 
contract NFTDAO is ERC721, ERC721Enumerable, ERC721Burnable, ERC721URIStorage, ReentrancyGuard{

    using Strings for uint256;
    using Counters for Counters.Counter;
   
    error TransferFailed();
 
    //mint variables
    uint public maxSupply;
    uint public mintPrice;
    uint public salaryAmout; //we may hard code this or set it the constructor or they select it like right now
    bool public mintLive;
    bool public dynamicMint;
    uint256 public expiry; // Whitelist expiry time i.e. 3600 - we not need this 
 
    uint256 public lastTimeStamp;
    uint256 public immutable intervalWeek = 120; //set for 2 minute updates 
    uint public immutable intervalMonth = 200;
 
    //basee uri attributes  
    string public baseURI;
    string public baseExtension = ".json";
 
    //DAO card attributes
    struct DAOAttributes {
        uint256 tokenID;
        uint256 birthtime;
        uint256 tier;
        string role; //set them all eqaul to the mod role or multiple roles but they can only use them if elected 
        uint256 modTime;
    }

    //DAO card mapped to a token ID
    mapping (uint256 => DAOAttributes) public dAOCardAtrributes;

    //role variables 
    mapping(bytes32 => mapping(uint256 => bool)) public currentMods;
    //mapping(bytes32 => mapping(Canidates => bool)) public currentMods;
    
    bytes32 public constant MOD_ROLE = keccak256("MOD_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");

    //election variables 
    enum ElectionState {
        //OPEN,
        CALCULATING 
    }

    ElectionState private s_electionState;

    //DAO/Election variables
    address public owner;
 
    struct Candidate {
        uint id; //proposel id
        address candidate; //canidate
        uint amount; //salary - function - this is not voted on in stead it is preset
        string name;
        string description; //why you are running  
        uint startBlock; 
        uint endBlock;
        uint yesVotes;
        uint noVotes;
        bool isLive; 
        bool isElected;
        bool isExecuted;
        //one more token ID - parameter for function 
    }

    mapping (uint => Candidate) public candidates;
    mapping (address => uint) public lastCandidate;

    //do we need this 
    mapping (address => uint[]) public candidateList;   

    address payable[] private s_candidates;               

    //we technically need this for double voting but its not working
    mapping(uint => mapping(address => bool)) public voterHistory;
 
    uint public totalVotesThreshold; //how many votes are needed to pass a proposel
    uint public voterNFTThreshold = 1;
    uint public candidateNFTThreshold;
 
    //tiers //we might want to get rid of these or store them in memory somehow
    uint public supplyThreshold;
    uint public supplyThresholdTwo;
    uint public supplyThresholdThree;
 
    uint public totalCandidates;
    uint public candidatesPassed;

    //for testing purposes we are going to get rid of this timelock type thing for now
    //uint public blocksPerDay = 6500;
    uint public electionWindow = 60;
 
    Counters.Counter private _tokenIdCounter;
 
    constructor(
       
    string memory  _name,
    string memory _symbol,
    uint _maxSupply,
    uint _totalVotesThreshold,
    uint _candidateNFTThreshold,
    //uint256 _interval,
    address _owner
 
    ) ERC721(_name,  _symbol) {
        maxSupply = _maxSupply;
        owner = _owner;
        totalVotesThreshold = _totalVotesThreshold;
        candidateNFTThreshold = _candidateNFTThreshold;
        //interval = _interval;
 
    }
    //proposel threshold
 
    //events
    event Mint(address indexed _from, uint _id);
 
    event CandidateCreated(address indexed _from, uint _id);
 
    event CandidateElected(bool _passed, address indexed _to, uint _amount, uint _id);
 
    event VoteCast(address indexed _from, bool _yes, uint _id);
 
    event OwnershipTransferred(address indexed _from, address indexed _to);
 
    //event CurrentPrice(uint256 indexed price);
 
    function needToUpdateCost(uint256 _supply) internal view returns (uint256 _cost){
 
        if(dynamicMint){
 
            if(_supply < 2){
          //returns our value in wei ether key word indicate
            return 2 ether;
            }
 
            if(_supply < 3){
            //returns our value in wei ether key word indicates
            return 4 ether;
            }
 
            if(_supply <= maxSupply){
 
            //returns our value in wei ether key word indicates
            return 8 ether;
            }
 
        }
        else {

            return mintPrice;
        }
           
    }
    //mint
    function mint(uint _mintAmount) public payable {
 
        uint256 currentSupply = totalSupply();
     
        require(mintLive, "Mint isn't live");
 
        require(_mintAmount > 0, "Insert mint amount");
 
        require(currentSupply + _mintAmount <= maxSupply, "max NFT limit exceeded");
 
        require(msg.value >= needToUpdateCost(currentSupply) * _mintAmount, "insufficient funds");
 
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        for (uint i = 1; i <= _mintAmount; i++) {
            currentSupply += 1; //why dont i just iterate this or increment it or use the loop?
        }
        _safeMint(msg.sender, tokenId);

        dAOCardAtrributes[tokenId] = DAOAttributes ({
                tokenID: tokenId,
                birthtime: block.timestamp,
                tier: 1, //this will also be a memory variable based on tiers stringify numbers
                role: "string",  //make sure this is more gas efficient then the other way
                modTime: 100
            });          
        emit Mint(msg.sender, tokenId);       
    }

    // set mint type
    function setMint( uint _amount, bool _mintLive, bool _dynamicMint) public onlyOwner {
        mintPrice = _amount;
        mintLive = _mintLive;
        dynamicMint = _dynamicMint;
    }
 
    //set tiers for mint
    function setMintTiers(uint256 _tierOne, uint256 _tier2, uint256 _tier3) public onlyOwner {
        require(dynamicMint);
        supplyThreshold = _tierOne;
        supplyThresholdTwo = _tier2;
        supplyThresholdThree =_tier3;
    }
 
    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        //this is where the URI funcs are going to go
 
    }
 
    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }
 
    //DAO
    modifier onlyOwner() {
        require(msg.sender==owner);
        _;
    }
 
    function transferOwner(address _newOwner) public onlyOwner{
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    function enterElection (uint _amount, string memory _ipfsHash, string memory _name, uint256 _tokenID) public {
        require(balanceOf(msg.sender) >= candidateNFTThreshold, "Use doesn't have enough NFTs to be elected");
        require(s_electionState != ElectionState.CALCULATING, "Raffle is not open");
        require(lastCandidate[msg.sender] == 0, "Only 1 proposal per user");
 
        Candidate memory _candidate;
 
        _candidate.id = totalCandidates+1; //could we make this tokenID instead is it redundant
        _candidate.candidate = msg.sender;
        _candidate.amount = _amount;
        _candidate.name = _name;
        _candidate.description = _ipfsHash;
        _candidate.startBlock = block.timestamp; //we do have this?
        _candidate.endBlock = block.timestamp + electionWindow;

        //dowe need this
        _candidate.isLive = true;
 
        candidates[_candidate.id] = _candidate;
        lastCandidate[msg.sender] = _candidate.id;

        //do we need this
        totalCandidates +=1;
        //do we need this
        candidateList[msg.sender].push(candidates);
 
        emit CandidateCreated(msg.sender, _candidate.id);
 
    }
    //settle proposal
    function electCandidate(uint _candidateId) public {
        require(block.timestamp > candidates[_candidateId].endBlock, "Proposal still open");
        require(candidates[_candidateId].isExecuted == false, "Proposal already executed");
        require(candidates[_candidateId].id != 0, "Proposal doesn't exist");
 
        //need to replace this with enum open closed for example 
        candidates[_candidateId].isLive = false;

        //candidtates list 

        uint totalVotes = candidates[_candidateId].yesVotes + candidates[_candidateId].noVotes;
        if (totalVotes <= totalVotesThreshold) {
            candidates[_candidateId].isExecuted = true;
            delete lastCandidate[msg.sender];
            emit CandidateElected(false, owner, 0, _candidateId);
        } else {
            if (candidates[_candidateId].yesVotes > candidates[_candidateId].noVotes) {
                candidates[_candidateId].isElected = true;
                //we are going to camp back to this for now leave it - this is where we select the candidate
                require(address(this).balance > candidates[_candidateId].amount, "Contract doesn't have enough funds for mod salary");
                //right now it should send the owner money its not going to elect a mod until we put the uri in their
                (bool sent, bytes memory data) = owner.call{value: candidates[_candidateId].amount}("");
                require(sent, "Failed to send Ether");

                uint256 indexOfWinner = randomWords[0] % s_players.length; //index of candidate who got the most votes
                address payable recentWinner = s_players[indexOfWinner];
                s_recentWinner = recentWinner;
                s_players = new address payable[](0);
                s_raffleState = RaffleState.OPEN;
                s_lastTimeStamp = block.timestamp;
                (bool success, ) = recentWinner.call{value: address(this).balance}("");

                candidates[_candidateId].isExecuted = true;
                delete lastCandidate[msg.sender];
                //another call point for mod rights in moralis could be here -- this event happening --
                emit CandidateElected(true, owner, candidates[_candidateId].amount, _candidateId);
 
            } else {
                candidates[_candidateId].isExecuted = true;
                delete lastCandidate[msg.sender];
                emit CandidateElected(false, owner, 0, _candidateId);
            }
        }
    }

    function getNumberOfCandidates () public view returns (uint) {
        returns candidatesList.length; 
    }

    function calculateWeight(uint256 tokenID) internal view returns (uint256) {
 
        uint256 stakeTime;
        uint256 points;
        uint256 timePassed = 120; //2months //2628000; //1 month //make this custom  
        uint256 tokenBirth = dAOCardAtrributes[tokenID].birthtime;
        stakeTime = block.timestamp - tokenBirth;
        if(stakeTime < timePassed){ 

            revert TransferFailed();
        }
        else {
 
            points = stakeTime / timePassed;
        }
       
        return points;
        // we should really divided points to an average of total minted supply and also look at quorum at first chance
 
    }
 
    function vote(bool _yes, uint _candidateId, uint256 tokenID) public {
 
        require(balanceOf(msg.sender) >= voterNFTThreshold, "Use doesn't have enough NFTs to vote");
        require(ownerOf(tokenID) == msg.sender, "not owner"); //i think this is redundant it was not working because 1 index is 0
        require(candidates[_candidateId].isLive, "Proposal is closed");
        require(block.timestamp < candidates[_candidateId].endBlock, "Voting window is closed");
        //this is not working for some reason
        require(voterHistory[_candidateId][msg.sender] == false, "User already voted");

        //there are no "no" votes in an election only yes votes
 
        if (_yes) {
            //proposals[_proposalId].yesVotes +=1; //= users token ID weighted vote reward = dAOattributes[nftId] = Attributes.weight    
            candidates[_candidateId].yesVotes += calculateWeight(tokenID);
            emit VoteCast(msg.sender, true, _candidateId);
        } else {
            //proposals[_proposalId].noVotes +=1; //= users/token ID weighted vote = weighted[msg.sender]
            candidates[_candidateId].noVotes += calculateWeight(tokenID);
            emit VoteCast(msg.sender, false, _candidateId);
        }
 
         voterHistory[_candidateId][msg.sender] == true; //no idea how to solve this problem //maybe this has to be a modifier
    }




























//chainlink keepers 

//time based problems:;
// 
//the window to vote on an election with a candidate is 1 mintue - test this out - once the election starts its one minute
//after we one minute close the election and the results are calculates simply by calling the function 
//you can enter the election at any time I think 



//we perform checkupkeep to do two things one to open the election, it opens after 1 month 
//also to give automitc payots we do this every 4 weeks 
//if in check up a week has paseed perform upkeep will call the payout fucntion 
//if a month has passed perform upkeep will open election entires - see how they did this in raffle or it will just call execute
//maybe we open elections up a week before the final election and then perform upkeep on 4th week and we execute and close - the way our code is strucutred now people 
//cannot vote until the elections are "open" - now we could just chainge this to voting open ill have to see
//using the pass time thing we saw in aave gotchi we can actually make it graphically cool but also do things as time passes


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//if we end up having a a random selector componant to this electio
    function checkUpkeep(bytes calldata /* checkData */) external view returns (bool upkeepNeeded, bytes memory /* performData */)
    {

        //uint256 lastTimeStamp = gotchiHolderAttributes[0].lastChecked;
        //upkeepNeeded = (gotchiHolderAttributes[0].happiness > 0 && (block.timestamp - lastTimeStamp) > 60);
        //bool hasPlayers = s_players.length > 0;
        //bool isOpen = RaffleState.OPEN == s_raffleState;
        //bool hasMonthPassed = ((block.timestamp - lastTimeStamp) > intervalWeek); 

        //rather then having two if statements in the checkupkeep we could just call the function in the fourth intervalonce it hits zero 
        //it will be like our dead emojigotch


        bool hasWeekPassed = ((block.timestamp - lastTimeStamp) > intervalWeek); //set this to one week
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (hasWeekPassed && hasBalance);

        return (upkeepNeeded, "0x0"); // can we comment this out?

    }

    //we dont need to get a specific token for this - these conditions are true accross the entire protocal
    //we pay current mod and we call new elections thats what we have to d
    function performUpkeep(bytes calldata /* performData */) external 
    {
        //s_electionState = ElectionState.CALCULATING;

        //We highly recommend revalidating the upkeep in the performUpkeep function

        //in poerform up we need to elect our candidate at a triggered time - that election will somereturn a tokenID for a mod which we can pass in 
        //the emojigtochi functionss 

        //(bool upkeepNeeded, ) = checkUpkeep("");
        // require(upkeepNeeded, "Upkeep not needed");
        //we have to get the tokenID that was elected
        if (
            dAOCardAtrributes[_tokenId].modTime > 0 && //check to see if we can subtract //check to see if 
            ((block.timestamp - lastTimeStamp) > intervalWeek) //if 60 seconds has passed since last check
        ) {
            //reset the birth time of the emojigotchi with keepers
            gotchiHolderAttributes[0].lastChecked = block.timestamp;
            lastTimeStamp = block.timestamp; //this is how measure a week passing 
            passTime(0);
        }

        else if (
            ((block.timestamp - lastTimeStamp) > intervalWeek)
        ){

        }

        // We don't use the performData in this example. The performData is generated by the Keeper's call to your checkUpkeep function
    }

    function passTime(uint256 _tokenId) public {
        dAOCardAtrributes[_tokenId].modTime =
        dAOCardAtrributes[_tokenId].modTime -
        25;

        updateURI(_tokenId);
        //emitUpdate(_tokenId);
    }

//////////////////URI FUNCTIONS ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    function updateURI(uint256 _tokenId) private {
        //string memory emojiB64 = emojiBase64[0]; //store mod uri
        if (dAOCardAtrributes[_tokenId].modTime == 100) {
            //set the mod uri
            //send payment 
            //assign role
        } else if (dAOCardAtrributes[_tokenId].modTime == 85) {
            //send payment 
        } else if (dAOCardAtrributes[_tokenId].modTime == 50) {
             //send payment 
        } else if (dAOCardAtrributes[_tokenId].modTime  == 25) {
             //send payment 
        } else if (dAOCardAtrributes[_tokenId].modTime  == 0) {
            //Set Back URI
            //send payment 
            //revoke role
        }
        //string memory finalSVG = string(abi.encodePacked(SVGBase, emojiB64));
        //dAOCardAtrributes[_tokenId].imageURI = finalSVG;
        //_setTokenURI(_tokenId, tokenURI(_tokenId));
    }

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
        //check if burn then unstake
    }
 
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
 
    //receipt function
    function _burn (uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
        //unstake your funds - call unstake maybe aftertoken transfer
    }

    // Fund withdrawal function.
 
    function getbirthTimeStamp(uint256 tokenID) public view returns (uint256) {
        return dAOCardAtrributes[tokenID].birthtime;
    }
 
    function getcurrentTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }

}
