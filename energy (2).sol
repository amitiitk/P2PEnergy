// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

contract EnergyTrading {
    address public dso;
    uint256 public threshold;
  
    struct Ownership {
        address account;
        uint256 energyBalance;
        uint256 role; // 1 for Prosumer, 2 for Consumer 
    }

    struct MatchInfo {
        uint status;   // 0 for unavailble and 1 for avaiable  
        uint256 matchedAmount;
        uint256 price;
    }

    mapping(address => Ownership) public ownerships;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => MatchInfo)) public matchRecords;

    event OwnershipEvent(
        address indexed account,
        uint256 energyBalance,
        string role
    );
    event StakeholderRegistered(address indexed account, string role);
    event TransactionInitiated(uint256 energyAmount, uint256 price);
    event EnergyInjected(address indexed prosumer, uint256 energyAmount);
    event EnergyTraded(
        address indexed prosumer,
        address indexed consumer,
        uint256 energyAmount,
        uint256 price
    );
    event VerificationEvent(
        address indexed account,
        uint256 energyBalance,
        uint256 price,
        string role
    );
    event EnergyLossCalculated(uint256 energyLossPercentage);

    event MatchEvent(
        address indexed prosumer,
        address indexed consumer,
        uint256 prosumerEnergy,
        uint256 consumerEnergy
    );

    event TradingLog(
        address indexed prosumer,
        address indexed consumer,
        uint256 prosumerEnergyBefore,
        uint256 consumerEnergyBefore,
        uint256 prosumerEnergyAfter,
        uint256 consumerEnergyAfter,
        uint256 price
    );

    modifier onlyDSO() {
        require(msg.sender == dso, "Only DSO can call this function");
        _;
    }

    modifier onlyProsumer() {
        require(
            ownerships[msg.sender].role == 1,
            "Only prosumers can inject energy"
        );
        _;
    }

    constructor(address _dso, uint256 _threshold) public {
        dso = _dso;
        threshold = _threshold;
    }

    function registerNode(address account, uint256 role) public onlyDSO {
        require(account != address(0), "Invalid address");
        require(account != dso, "DSO is already registered");
        require(role == 1 || role == 2, "Invalid role");

        string memory roleString = role == 1 ? "Prosumer" : "Consumer";
        ownerships[account] = Ownership(account, 0, role);

        emit OwnershipEvent(account, 0, roleString);
        emit StakeholderRegistered(account, roleString);
    }
    function energyInjection(uint256 energyInjected) public onlyProsumer {
        ownerships[msg.sender].energyBalance += energyInjected; // Update total available energy

        emit EnergyInjected(msg.sender, energyInjected);
        emit OwnershipEvent(
            msg.sender,
            ownerships[msg.sender].energyBalance,
            "Prosumer"
        );
    }

    function matchProsumerConsumer(
        address prosumer,
        address consumer,
        uint256 tradeAmount,
        uint256 price
    ) public onlyDSO {
        uint256 totalMatchedAmount = 0;
        require(ownerships[prosumer].role == 1, "Address is not a prosumer");
        require(ownerships[consumer].role == 2, "Address is not a consumer");
        require(tradeAmount <= ownerships[prosumer].energyBalance, "Amount should be less than prosumer avaible energy");
        uint256 prosumerEnergyAvailable = ownerships[prosumer].energyBalance;
        uint256 consumerEnergyNeeded = tradeAmount;

        if (prosumerEnergyAvailable > 0 && consumerEnergyNeeded > 0) {
            uint256 matchedAmount = prosumerEnergyAvailable >=
                consumerEnergyNeeded
                ? consumerEnergyNeeded
                : prosumerEnergyAvailable;

                        // Store the trade data
            matchRecords[prosumer][consumer] = MatchInfo({
                status: 1,
                matchedAmount: matchedAmount,
                price: price
            });
            emit MatchEvent(
                prosumer,
                consumer,
                ownerships[prosumer].energyBalance,
                ownerships[consumer].energyBalance
            );
            emit EnergyTraded(prosumer, consumer, matchedAmount, price);
            emit TransactionInitiated(matchedAmount, price);
        }
    }

    function energyTrading(
        address prosumer,
        address consumer
    ) public onlyDSO {
        require(matchRecords[prosumer][consumer].status == 1, "No match record found");
        require(ownerships[prosumer].role == 1, "Address is not a prosumer");
        require(ownerships[consumer].role == 2, "Address is not a consumer");

        uint256 matchedAmount = _matchEnergy(prosumer, consumer);

        if (matchedAmount > 0) {
            _executeTrade(prosumer, consumer, matchedAmount);
        }
        matchRecords[prosumer][consumer] = MatchInfo({
                status: 0,
                matchedAmount: 0,
                price: 0
        });
    }

    function _matchEnergy(address prosumer, address consumer)
        internal
        view
        returns (uint256)
    {
        require(matchRecords[prosumer][consumer].status == 1, "No match record found");
        uint256 prosumerEnergyAvailable = ownerships[prosumer].energyBalance;
        uint256 consumerEnergyNeeded = matchRecords[prosumer][consumer].matchedAmount;

        if (prosumerEnergyAvailable > 0 && consumerEnergyNeeded > 0) {
            return
                prosumerEnergyAvailable >= consumerEnergyNeeded
                    ? consumerEnergyNeeded
                    : prosumerEnergyAvailable;
        }

        return 0;
    }

    function _executeTrade(
        address prosumer,
        address consumer,
        uint256 matchedAmount
    ) internal {
        uint256 prosumerEnergyBefore = ownerships[prosumer].energyBalance;
        uint256 consumerEnergyBefore = ownerships[consumer].energyBalance;

        ownerships[prosumer].energyBalance -= matchedAmount;
        ownerships[consumer].energyBalance += matchedAmount;

        balances[prosumer] += matchedAmount * matchRecords[prosumer][consumer].price;
        balances[consumer] -= matchedAmount * matchRecords[prosumer][consumer].price;

        emit TradingLog(
            prosumer,
            consumer,
            prosumerEnergyBefore,
            consumerEnergyBefore,
            ownerships[prosumer].energyBalance,
            ownerships[consumer].energyBalance,
            matchRecords[prosumer][consumer].price
        );

        emit EnergyTraded(prosumer, consumer, matchedAmount, matchRecords[prosumer][consumer].price);
    }

    function verifyTransaction(string memory transactionType, address account)
        public
        onlyDSO
    {
        Ownership memory owner = ownerships[account];
        string memory roleString = owner.role == 0 ? "Prosumer" : "Consumer";
        emit VerificationEvent(
            account,
            owner.energyBalance,
            balances[account],
            roleString
        );
    }

    function calculateEnergyLoss(uint256 E_source, uint256 E_destination)
        public
        returns (uint256)
    {
        require(E_source != 0, "Energy source cannot be zero");
        uint256 E_loss = E_source - E_destination;
        uint256 energyLossPercentage = (E_loss * 100) / E_source;
        if (energyLossPercentage > threshold) {
            adjustEnergyDistributionPathways();
            optimizeEnergyRoutingUsingRealTimeDataAnalytics();
            notifyStakeholdersOfRequiredAdjustments();
        } else {
            continueWithCurrentEnergyDistributionPathways();
        }
        emit EnergyLossCalculated(energyLossPercentage);
        return energyLossPercentage;
    }

    function adjustEnergyDistributionPathways() internal {
        // Implement logic to adjust energy distribution pathways
    }

    function optimizeEnergyRoutingUsingRealTimeDataAnalytics() internal {
        // Implement logic to optimize energy routing using real-time data analytics
    }

    function notifyStakeholdersOfRequiredAdjustments() internal {
        // Implement logic to notify stakeholders of required adjustments
    }

    function continueWithCurrentEnergyDistributionPathways() internal {
        // Implement logic to continue with current energy distribution pathways
    }
}

