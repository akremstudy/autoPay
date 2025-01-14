// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

/**
 @author Tellor Inc.
 @title Autopay
 @dev This is contract for automatically paying for Tellor oracle data at
 * specific time intervals. Any non-rebasing ERC20 token can be used for payment.
 * Only the first data submission within each time window gets a reward.
*/
import "usingtellor/contracts/UsingTellor.sol";
import "./interfaces/IERC20.sol";
contract Autopay is UsingTellor {
    // Storage
    ITellor public master; // Tellor contract address
    IERC20 public token; // TRB token address
    address public owner;
    uint256 public fee; // 1000 is 100%, 50 is 5%, etc.

    mapping(bytes32 => mapping(bytes32 => Feed)) dataFeed; // mapping queryId to dataFeedId to details
    mapping(bytes32 => bytes32[]) currentFeeds; // mapping queryId to dataFeedIds array
    mapping(bytes32 => Tip[]) public tips; // mapping queryId to tips
    mapping(bytes32 => bytes32) public queryIdFromDataFeedId; // mapping dataFeedId to queryId
    mapping(bytes32 => uint256) public queryIdsWithFundingIndex; // mapping queryId to queryIdsWithFunding index plus one (0 if not in array)
    mapping(bytes32 => KeeperTip) public keeperTips; // mapping queryId to keeperTip
    mapping(bytes32 => mapping(bytes32 => KeeperJobDetails)) jobs; // mapping jobId to queryId to JobDetails
    bytes32[] public feedsWithFunding; // array of dataFeedIds that have funding
    bytes32[] public queryIdsWithFunding; // array of queryIds that have funding

    // Structs
    struct FeedDetails {
        uint256 reward; // amount paid for each eligible data submission
        uint256 balance; // account remaining balance
        uint256 startTime; // time of first payment window
        uint256 interval; // time between pay periods
        uint256 window; // amount of time data can be submitted per interval
        uint256 priceThreshold; //change in price necessitating an update 100 = 1%
        uint256 feedsWithFundingIndex; // index plus one of dataFeedID in feedsWithFunding array (0 if not in array)
    }

    struct Feed {
        FeedDetails details;
        mapping(uint256 => bool) rewardClaimed; // tracks which tips were already paid out
    }

    struct Tip {
        uint256 amount;
        uint256 timestamp;
    }

    struct KeeperTip {
        uint256 amount;
        uint256 timestamp; // current timestamp
        uint256 timeToCallIt; // Timestamp for when to call the function after
        uint256 maxGasCover; // Max gas price keeper is recommended to pay in payment token
        address creator;
    }

    struct KeeperJobDetails {
        uint256 timeToCallIt;
        uint256 interval;
        uint256 window;
        uint256 payment;
        uint256 balance;
        uint256 maxGasCover;
    }

    // Events
    event NewDataFeed(
        bytes32 _queryId,
        bytes32 _feedId,
        bytes _queryData,
        address _feedCreator
    );
    event DataFeedFunded(
        bytes32 _queryId,
        bytes32 _feedId,
        uint256 _amount,
        address _feedFunder
    );
    event OneTimeTipClaimed(
        bytes32 _queryId,
        uint256 _amount,
        address _reporter
    );
    event TipAdded(
        bytes32 _queryId,
        uint256 _amount,
        bytes _queryData,
        address _tipper
    );
    event TipClaimed(
        bytes32 _feedId,
        bytes32 _queryId,
        uint256 _amount,
        address _reporter
    );
    event KeeperTipAdded(
        uint256 _amount,
        bytes32 _queryId,
        bytes _queryData,
        address _tipper
    );
    event KeeperTipClaimed(
        bytes32 _queryId,
        uint256 _amount,
        address _keeper
    );
    event NewKeeperJob (
        address _creator,
        bytes32 _jobId,
        bytes _queryData,
        bytes32 _queryId,
        uint256 _payment
    );
    event KeeperJobFunded (
        address _creator,
        uint256 _amount,
        bytes32 _queryId,
        bytes32 _jobId
    );
    event JobPaid(
        bytes32 _jobId,
        bytes32 _queryId,
        uint256 _payment,
        address _keeper
    );
    event JobRemoved(
        bytes32 _queryId,
        address _creator
    );
    event AddedExtraTiptoJob(
        uint256 _amount,
        bytes32 _queryId,
        address _creator
    );
    event MaxGasCoverIncreased(
        uint256 _amount,
        bytes32 _queryId,
        address _creator
    );


    // Functions
    /**
     * @dev Initializes system parameters
     * @param _tellor address of Tellor contract
     * @param _owner address of fee recipient
     * @param _fee percentage, 1000 is 100%, 50 is 5%, etc.
     */
    constructor(
        address payable _tellor,
        address _token,
        address _owner,
        uint256 _fee
    ) UsingTellor(_tellor) {
        master = ITellor(_tellor);
        token = IERC20(_token);
        owner = _owner;
        fee = _fee;
    }


    /** 
    * @dev Function to tip keepers to call a function
    * @param _maxGasCover The amount of gas covered by creator in payment token
    * @param _contractAddress The smart contract address where the function is to be called
    * @param _functionSig The function signature data
    * @param _timeToCallIt The timestamp of when to trigger the function
    * @param _chainId The chain id
    * @param _tip Amount to tip
    */
    function tipKeeperJob(
        uint256 _maxGasCover,
        address _contractAddress,
        bytes calldata _functionSig,
        uint256 _timeToCallIt,
        uint256 _chainId,
        uint256 _tip)
        external {
            string memory _type = "TellorKpr";
            bytes memory _encodedArgs = abi.encode(_maxGasCover,_contractAddress,_functionSig,_timeToCallIt,_chainId);
            bytes memory _queryData = abi.encode(_type,_encodedArgs);
            bytes32 _queryId = keccak256(_queryData);
            uint256 _amount;
            if (keeperTips[_queryId].amount == 0) {
                _amount = _tip + _maxGasCover;
                keeperTips[_queryId] = (KeeperTip(_tip, block.timestamp, _timeToCallIt, _maxGasCover, msg.sender));
            } else {
                keeperTips[_queryId].amount += _tip;
                _amount = _tip;
            }
            // transfer tip plus gasCover to this contract address
            require(
            token.transferFrom(msg.sender, address(this), _amount),
            "ERC20: transfer amount exceeds balance"
            );
            emit KeeperTipAdded(_tip, _queryId, _queryData, msg.sender);
    }

    function increaseMaxGasForExistingJob(bytes32 _queryId, uint256 _amount) external {
        KeeperTip storage _keep = keeperTips[_queryId];
        require(_keep.maxGasCover > 0,"Job not setup yet");
        require(msg.sender == _keep.creator, "Not job creator");
        _keep.maxGasCover += _amount;
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "ERC20: transfer amount exceeds balance"
            );
        emit MaxGasCoverIncreased(_amount, _queryId, msg.sender);
        }

    function addTiptoExistingSingleJob(bytes32 _queryId, uint256 _amount) external {
        KeeperTip storage _keep = keeperTips[_queryId];
        require(msg.sender == _keep.creator || msg.sender == owner, "Not job creator");
        require(_keep.amount > 0, "Job doesn't exist");
        _keep.amount += _amount;
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "ERC20: transfer amount exceeds balance"
            );
        emit AddedExtraTiptoJob(_amount, _queryId, msg.sender);
    }

    function unclaimedSingleTipsFallback(bytes32 _queryId) external {
        KeeperTip storage _keep = keeperTips[_queryId];
        require((block.timestamp - _keep.timeToCallIt) >  12 weeks, "Wait 12 weeks to get unclaimed tips");
        require(msg.sender == _keep.creator, "Not your job");
        require(_keep.amount > 0, "There are no tips to claim");
        require(
            token.transfer(msg.sender, _keep.amount + _keep.maxGasCover)
            );
        _keep.amount = 0;
        emit JobRemoved(_queryId, msg.sender);
    }
    /**
    * @dev Function for claiming a single function call tip
    * @param _queryId ID of query to claim tip for
    */
    function keeperClaimTip(bytes32 _queryId) external {
        uint256 _timestamp = getTimestampbyQueryIdandIndex(_queryId, 0);
        KeeperTip memory _keeperTips = keeperTips[_queryId];
        require(
            block.timestamp - _timestamp > 12 hours,
            "buffer time has not passed"
        );
        bytes memory _valueRetrieved = retrieveData(_queryId, _timestamp);
        require(
            keccak256(_valueRetrieved) != keccak256(bytes("")),
            "no value exists at timestamp"
        );
        ( , address _keeperAddress, uint256 _whenItWasCalled, uint256 _gasPaid) = abi.decode(_valueRetrieved, (bytes32,address,uint256,uint256));
        // require submitted timestamp is after submit timestamp
        uint256 _whenToCallIt = _keeperTips.timeToCallIt;
        require(_whenItWasCalled > _whenToCallIt, "Function called before its time!");
        uint256 _tipAmount;
        require(_keeperTips.amount > 0, "tips already claimed");
        if (_gasPaid >= _keeperTips.maxGasCover) {
            _tipAmount = _keeperTips.amount + _keeperTips.maxGasCover;
        } else {
            _tipAmount = _gasPaid + _keeperTips.amount;
            require(token.transfer(_keeperTips.creator, (_keeperTips.maxGasCover - _gasPaid)));
        }
        
        require(token.transfer(_keeperAddress, _tipAmount - ((_tipAmount * fee) / 1000)));
        require(token.transfer(owner, (_tipAmount * fee) / 1000));
        emit KeeperTipClaimed(_queryId, _tipAmount, _keeperAddress);
    }
    // function getJobBalance() external view returns { return _job.balance}
    /**
    @dev Function for setting up a function call job
    @param _contractAddress Address of smart contract
    @param _functionSig Function signature data
    @param _maxGasCovered Maximum amount of gas a keeper is able to claim
    @param _timeToCallIt Timestamp of when the function needs to be called
    @param _chainId Chain ID for the chain where the contract exists
    @param _window Time in seconds of the size of window for when the function needs to be triggered
    @param _interval Time in seconds of how often the function needs to be triggered
    @param _payment Payment amount for each function call
    */
    function setupKeeperJob(
        address _contractAddress,
        bytes calldata _functionSig,
        uint256 _maxGasCovered,
        uint256 _timeToCallIt,
        uint256 _chainId,
        uint256 _window, 
        uint256 _interval,
        uint256 _payment
        ) external {
            string memory _type = "TellorKpr";
            bytes memory _encodedArgs = abi.encode(_contractAddress,_functionSig,_timeToCallIt,_chainId,_maxGasCovered);
            bytes memory _queryData = abi.encode(_type,_encodedArgs);
            bytes32 _queryId = keccak256(_queryData);
            require(_payment > 0, "No free keeping");
            require(_interval > _window, "Interval has to be greater than window");

            bytes32 _jobId = keccak256(abi.encode(
                _queryId,
                _timeToCallIt,
                _window,
                _interval,
                _payment,
                _maxGasCovered
            ));
            KeeperJobDetails storage _job = jobs[_jobId][_queryId];
            require(_job.payment == 0, "job id already exists, fund Job");
            _job.timeToCallIt = _timeToCallIt;
            _job.interval = _interval;
            _job.window = _window;
            _job.payment = _payment;
            _job.maxGasCover = _maxGasCovered;
  
            emit NewKeeperJob(msg.sender, _jobId, _queryData, _queryId, _payment);

    }
    
    /**
    @dev Function for funding jobs that have already been setup
    @param _amount Amount of payment for calling the function excluding gas
    @param _queryId ID of function data and details
    @param _jobId ID of queryId and function(job) details
    */
    function fundJob(
        uint256 _amount,
        bytes32 _queryId,
        bytes32 _jobId
    ) external {
        KeeperJobDetails storage _job = jobs[_jobId][_queryId];
        require(_job.payment > 0, "Job hasn't been setup");
        uint256 _tipAndGas = _amount + _job.maxGasCover;
        require(_tipAndGas > _job.payment, "Not enough to cover payment");
        _job.balance += _tipAndGas;
        require(token.transferFrom(msg.sender, address(this), _tipAndGas), "ERC20: transfer amount exceeds balance");
        emit KeeperJobFunded(msg.sender, _amount, _queryId, _jobId);
    }

    /**
    @dev Function for claiming tips for jobs, can be called by anyone
    @param _jobId Hash of the queryId and the job details
    @param _queryId Id of reported data
    */
    function claimJobTips(bytes32 _jobId, bytes32 _queryId) external {
        KeeperJobDetails storage _job = jobs[_jobId][_queryId];
        ( , , uint256 _timestampBeforeStart) = getDataBefore(_queryId, _job.timeToCallIt);
        // getTimestampIndexByTimestamp
        uint256 _beginTimestampIndex = master.getTimestampIndexByTimestamp(_queryId, _timestampBeforeStart + 1);
        // getNewValueCountbyQueryId
        uint256 _timestampsCount = getNewValueCountbyQueryId(_queryId);
        for(uint i = _beginTimestampIndex; i < _timestampsCount; i++) {
            uint256 _paymentAmount;
            uint256 _submissionTimestamp = getTimestampbyQueryIdandIndex(_queryId, i);
            bytes memory _valueRetrieved = retrieveData(_queryId, _submissionTimestamp);
            ( , address _keeperAddress, uint256 _whenItWasCalled, uint256 _gasPaid) = abi.decode(_valueRetrieved, (bytes32,address,uint256,uint256));
            uint256 _interval = (_whenItWasCalled - _job.timeToCallIt) / _job.interval; // finds closest interval _n to timestamp
            uint256 _window = _job.timeToCallIt + _job.interval * _interval;
            if((_whenItWasCalled - _window) < _job.window) {
                // if balance > 0
                // TODO: add buffer
                if (_gasPaid >= _job.maxGasCover) {
                    _paymentAmount = _job.payment + _job.maxGasCover;
                } else {
                    _paymentAmount = _job.payment + _gasPaid;
                }
                _job.balance -= _paymentAmount;
                require(token.transfer(_keeperAddress, _paymentAmount - ((_paymentAmount * fee) / 1000)));
                require(token.transfer(owner, (_paymentAmount * fee) / 1000));
                emit JobPaid(_jobId, _queryId, _paymentAmount, _keeperAddress);
            }
        }
    }

    /**
     * @dev Function to claim singular tip
     * @param _queryId id of reported data
     * @param _timestamps[] batch of timestamps array of reported data eligible for reward
     */
    function claimOneTimeTip(bytes32 _queryId, uint256[] calldata _timestamps)
        external
    {
        require(
            tips[_queryId].length > 0,
            "no tips submitted for this queryId"
        );
        uint256 _reward;
        uint256 _cumulativeReward;
        for (uint256 _i = 0; _i < _timestamps.length; _i++) {
            (_reward) = _claimOneTimeTip(_queryId, _timestamps[_i]);
            _cumulativeReward += _reward;
        }
        require(
            token.transfer(
                msg.sender,
                _cumulativeReward - ((_cumulativeReward * fee) / 1000)
            )
        );
        require(token.transfer(owner, (_cumulativeReward * fee) / 1000));
        if (getCurrentTip(_queryId) == 0) {
            if (queryIdsWithFundingIndex[_queryId] != 0) {
                uint256 _idx = queryIdsWithFundingIndex[_queryId] - 1;
                // Replace unfunded feed in array with last element
                queryIdsWithFunding[_idx] = queryIdsWithFunding[
                    queryIdsWithFunding.length - 1
                ];
                bytes32 _queryIdLastFunded = queryIdsWithFunding[_idx];
                queryIdsWithFundingIndex[_queryIdLastFunded] = _idx + 1;
                queryIdsWithFundingIndex[_queryId] = 0;
                queryIdsWithFunding.pop();
            }
        }
        emit OneTimeTipClaimed(_queryId, _cumulativeReward, msg.sender);
    }

    /**
     * @dev Allows Tellor reporters to claim their tips in batches
     * @param _feedId unique feed identifier
     * @param _queryId ID of reported data
     * @param _timestamps[] batch of timestamps array of reported data eligible for reward
     */
    function claimTip(
        bytes32 _feedId,
        bytes32 _queryId,
        uint256[] calldata _timestamps
    ) external {
        uint256 _reward;
        uint256 _cumulativeReward;
        for (uint256 _i = 0; _i < _timestamps.length; _i++) {
            _reward = _claimTip(_feedId, _queryId, _timestamps[_i]);
            require(
                master.getReporterByTimestamp(_queryId, _timestamps[_i]) ==
                    msg.sender,
                "reporter mismatch"
            );
            _cumulativeReward += _reward;
        }
        require(
            token.transfer(
                msg.sender,
                _cumulativeReward - ((_cumulativeReward * fee) / 1000)
            )
        );
        require(token.transfer(owner, (_cumulativeReward * fee) / 1000));
        emit TipClaimed(_feedId, _queryId, _cumulativeReward, msg.sender);
    }

    /**
     * @dev Allows dataFeed account to be filled with tokens
     * @param _feedId unique feed identifier
     * @param _queryId identifier of reported data type associated with feed
     * @param _amount quantity of tokens to fund feed
     */
    function fundFeed(
        bytes32 _feedId,
        bytes32 _queryId,
        uint256 _amount
    ) external {
        FeedDetails storage _feed = dataFeed[_queryId][_feedId].details;
        require(_feed.reward > 0, "feed not set up");
        _feed.balance += _amount;
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "ERC20: transfer amount exceeds balance"
        );
        // Add to array of feeds with funding
        if (_feed.feedsWithFundingIndex == 0 && _feed.balance > 0) {
            feedsWithFunding.push(_feedId);
            _feed.feedsWithFundingIndex = feedsWithFunding.length;
        }
        emit DataFeedFunded(_feedId, _queryId, _amount, msg.sender);
    }

    /**
     * @dev Initializes dataFeed parameters.
     * @param _queryId unique identifier of desired data feed
     * @param _reward tip amount per eligible data submission
     * @param _startTime timestamp of first autopay window
     * @param _interval amount of time between autopay windows
     * @param _window amount of time after each new interval when reports are eligible for tips
     * @param _priceThreshold amount price must change to automate update regardless of time (negated if 0, 100 = 1%)
     * @param _queryData the data used by reporters to fulfill the query
     */
    function setupDataFeed(
        bytes32 _queryId,
        uint256 _reward,
        uint256 _startTime,
        uint256 _interval,
        uint256 _window,
        uint256 _priceThreshold,
        bytes calldata _queryData
    ) external {
        require(
            _queryId == keccak256(_queryData) || uint256(_queryId) <= 100,
            "id must be hash of bytes data"
        );
        bytes32 _feedId = keccak256(
            abi.encode(
                _queryId,
                _reward,
                _startTime,
                _interval,
                _window,
                _priceThreshold
            )
        );
        FeedDetails storage _feed = dataFeed[_queryId][_feedId].details;
        require(_feed.reward == 0, "feed must not be set up already");
        require(_reward > 0, "reward must be greater than zero");
        require(
            _window < _interval,
            "window must be less than interval length"
        );
        _feed.reward = _reward;
        _feed.startTime = _startTime;
        _feed.interval = _interval;
        _feed.window = _window;
        _feed.priceThreshold = _priceThreshold;

        currentFeeds[_queryId].push(_feedId);
        queryIdFromDataFeedId[_feedId] = _queryId;
        emit NewDataFeed(_queryId, _feedId, _queryData, msg.sender);
    }

    /**
     * @dev Function to run a single tip
     * @param _queryId ID of tipped data
     * @param _amount amount to tip
     * @param _queryData the data used by reporters to fulfill the query
     */
    function tip(
        bytes32 _queryId,
        uint256 _amount,
        bytes calldata _queryData
    ) external {
        require(
            _queryId == keccak256(_queryData) || uint256(_queryId) <= 100,
            "id must be hash of bytes data"
        );
        Tip[] storage _tips = tips[_queryId];
        if (_tips.length == 0) {
            _tips.push(Tip(_amount, block.timestamp));
        } else {
            (, , uint256 _timestampRetrieved) = getCurrentValue(_queryId);
            if (_timestampRetrieved < _tips[_tips.length - 1].timestamp) {
                _tips[_tips.length - 1].timestamp = block.timestamp;
                _tips[_tips.length - 1].amount += _amount;
            } else {
                _tips.push(Tip(_amount, block.timestamp));
            }
        }
        if (
            queryIdsWithFundingIndex[_queryId] == 0 &&
            getCurrentTip(_queryId) > 0
        ) {
            queryIdsWithFunding.push(_queryId);
            queryIdsWithFundingIndex[_queryId] = queryIdsWithFunding.length;
        }
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "ERC20: transfer amount exceeds balance"
        );
        emit TipAdded(_queryId, _amount, _queryData, msg.sender);
    }

    // Getters
    /**
     * @dev Getter function to read current data feeds
     * @param _queryId id of reported data
     * @return feedIds array for queryId
     */
    function getCurrentFeeds(bytes32 _queryId)
        external
        view
        returns (bytes32[] memory)
    {
        return currentFeeds[_queryId];
    }

    /**
     * @dev Getter function to current oneTime tip by queryId
     * @param _queryId id of reported data
     * @return amount of tip
     */
    function getCurrentTip(bytes32 _queryId) public view returns (uint256) {
        (, , uint256 _timestampRetrieved) = getCurrentValue(_queryId);
        Tip memory _lastTip = tips[_queryId][tips[_queryId].length - 1];
        if (_timestampRetrieved < _lastTip.timestamp) {
            return _lastTip.amount;
        } else {
            return 0;
        }
    }

    /**
     * @dev Getter function to read a specific dataFeed
     * @param _feedId unique feedId of parameters
     * @return FeedDetails details of specified feed
     */
    function getDataFeed(bytes32 _feedId)
        external
        view
        returns (FeedDetails memory)
    {
        return (dataFeed[queryIdFromDataFeedId[_feedId]][_feedId].details);
    }

    /**
     * @dev Getter function for currently funded feeds
     */
    function getFundedFeeds() external view returns (bytes32[] memory) {
        return feedsWithFunding;
    }

    /**
     * @dev Getter function for queryIds with current one time tips
     */
    function getFundedQueryIds() external view returns (bytes32[] memory) {
        return queryIdsWithFunding;
    }

    /**
     * @dev Getter function to get number of past tips
     * @param _queryId id of reported data
     * @return count of tips available
     */
    function getPastTipCount(bytes32 _queryId) external view returns (uint256) {
        return tips[_queryId].length;
    }

    /**
     * @dev Getter function for past tips
     * @param _queryId id of reported data
     * @return Tip struct (amount/timestamp) of all past tips
     */
    function getPastTips(bytes32 _queryId)
        external
        view
        returns (Tip[] memory)
    {
        return tips[_queryId];
    }

    /**
     * @dev Getter function for past tips by index
     * @param _queryId id of reported data
     * @param _index uint index in the Tip array
     * @return amount/timestamp of specific tip
     */
    function getPastTipByIndex(bytes32 _queryId, uint256 _index)
        external
        view
        returns (Tip memory)
    {
        return tips[_queryId][_index];
    }

    /**
     * @dev getter function to lookup query IDs from dataFeed IDs
     * @param _feedId dataFeed unique identifier
     * @return corresponding query ID
     */
    function getQueryIdFromFeedId(bytes32 _feedId)
        external
        view
        returns (bytes32)
    {
        return queryIdFromDataFeedId[_feedId];
    }

    /**
     * @dev Getter function to read if a reward has been claimed
     * @param _feedId feedId of dataFeed
     * @param _queryId id of reported data
     * @param _timestamp id or reported data
     * @return bool rewardClaimed
     */
    function getRewardClaimedStatus(
        bytes32 _feedId,
        bytes32 _queryId,
        uint256 _timestamp
    ) external view returns (bool) {
        return dataFeed[_queryId][_feedId].rewardClaimed[_timestamp];
    }

    // Internal functions
    /**
     * @dev Internal function to read if a reward has been claimed
     * @param _b bytes value to convert to uint256
     * @return _number uint256 converted from bytes
     */
    function _bytesToUint(bytes memory _b)
        internal
        pure
        returns (uint256 _number)
    {
        for (uint256 i = 0; i < _b.length; i++) {
            _number = _number + uint8(_b[i]);
        }
    }

    /**
     ** @dev Internal function which allows Tellor reporters to claim their one time tips
     * @param _queryId id of reported data
     * @param _timestamp timestamp of one time tip
     * @return amount of tip
     */
    function _claimOneTimeTip(bytes32 _queryId, uint256 _timestamp)
        internal
        returns (uint256)
    {
        Tip[] storage _tips = tips[_queryId];
        require(
            block.timestamp - _timestamp > 12 hours,
            "buffer time has not passed"
        );
        require(
            msg.sender == master.getReporterByTimestamp(_queryId, _timestamp),
            "message sender not reporter for given queryId and timestamp"
        );
        bytes memory _valueRetrieved = retrieveData(_queryId, _timestamp);
        require(
            keccak256(_valueRetrieved) != keccak256(bytes("")),
            "no value exists at timestamp"
        );
        uint256 _min = 0;
        uint256 _max = _tips.length;
        uint256 _mid;
        while (_max - _min > 1) {
            _mid = (_max + _min) / 2;
            if (_tips[_mid].timestamp > _timestamp) {
                _max = _mid;
            } else {
                _min = _mid;
            }
        }
        (, , uint256 _timestampBefore) = getDataBefore(_queryId, _timestamp);
        require(
            _timestampBefore < _tips[_min].timestamp,
            "tip earned by previous submission"
        );
        require(
            _timestamp > _tips[_min].timestamp,
            "timestamp not eligible for tip"
        );
        require(_tips[_min].amount > 0, "tip already claimed");
        uint256 _tipAmount = _tips[_min].amount;
        _tips[_min].amount = 0;
        return _tipAmount;
    }

    /**
     * @dev Internal function which allows Tellor reporters to claim their autopay tips
     * @param _feedId of dataFeed
     * @param _queryId id of reported data
     * @param _timestamp timestamp of reported data eligible for reward
     * @return uint256 reward amount
     */
    function _claimTip(
        bytes32 _feedId,
        bytes32 _queryId,
        uint256 _timestamp
    ) internal returns (uint256) {
        Feed storage _feed = dataFeed[_queryId][_feedId];
        require(_feed.details.balance > 0, "insufficient feed balance");
        require(!_feed.rewardClaimed[_timestamp], "reward already claimed");
        require(
            block.timestamp - _timestamp > 12 hours,
            "buffer time has not passed"
        );
        require(
            block.timestamp - _timestamp < 12 weeks,
            "timestamp too old to claim tip"
        );
        bytes memory _valueRetrieved = retrieveData(_queryId, _timestamp);
        require(
            keccak256(_valueRetrieved) != keccak256(bytes("")),
            "no value exists at timestamp"
        );
        uint256 _n = (_timestamp - _feed.details.startTime) /
            _feed.details.interval; // finds closest interval _n to timestamp
        uint256 _c = _feed.details.startTime + _feed.details.interval * _n; // finds timestamp _c of interval _n
        (
            ,
            bytes memory _valueRetrievedBefore,
            uint256 _timestampBefore
        ) = getDataBefore(_queryId, _timestamp);
        uint256 _priceChange = 0; //price change from last value to current value
        if (_feed.details.priceThreshold != 0) {
            uint256 _v1 = _bytesToUint(_valueRetrieved);
            uint256 _v2 = _bytesToUint(_valueRetrievedBefore);
            if (_v2 == 0) {
                _priceChange = 10000;
            } else if (_v1 >= _v2) {
                _priceChange = (10000 * (_v1 - _v2)) / _v2;
            } else {
                _priceChange = (10000 * (_v2 - _v1)) / _v2;
            }
        }
        if (_priceChange <= _feed.details.priceThreshold) {
            require(
                _timestamp - _c < _feed.details.window,
                "timestamp not within window"
            );
            require(
                _timestampBefore < _c,
                "timestamp not first report within window"
            );
        }
        uint256 _rewardAmount;
        if (_feed.details.balance > _feed.details.reward) {
            _rewardAmount = _feed.details.reward;
            _feed.details.balance -= _feed.details.reward;
        } else {
            _rewardAmount = _feed.details.balance;
            _feed.details.balance = 0;
            // Adjust currently funded feeds
            if (feedsWithFunding.length > 1) {
                uint256 _idx = _feed.details.feedsWithFundingIndex - 1;
                // Replace unfunded feed in array with last element
                feedsWithFunding[_idx] = feedsWithFunding[
                    feedsWithFunding.length - 1
                ];
                bytes32 _feedIdLastFunded = feedsWithFunding[_idx];
                bytes32 _queryIdLastFunded = queryIdFromDataFeedId[
                    _feedIdLastFunded
                ];
                dataFeed[_queryIdLastFunded][_feedIdLastFunded]
                    .details
                    .feedsWithFundingIndex = _idx + 1;
            }
            feedsWithFunding.pop();
            _feed.details.feedsWithFundingIndex = 0;
        }
        _feed.rewardClaimed[_timestamp] = true;
        return _rewardAmount;
    }
}
