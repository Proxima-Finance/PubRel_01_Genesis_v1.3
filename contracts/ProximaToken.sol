// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @title : ProximaToken
 * @notice : Copied and modified from COMPOUND:
 * https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol
 * Modified by ProximusAlpha
 */

contract ProximaToken {
    /// @dev EIP-20 token name for this token
    string public constant name = "Proxima";

    /// @dev EIP-20 token symbol for this token
    string public constant symbol = "PXA";

    /// @dev EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @dev Total number of tokens in current circulation
    uint96 internal _totalSupply;

    /// @dev Total number of tokens burned
    uint96 internal _supplyBurned;

    /// @dev Allowance amounts on behalf of others
    mapping(address => mapping(address => uint96)) internal allowances;

    /// @dev Official record of token balances for each account
    mapping(address => uint96) internal balances;

    /// @dev A record of each accounts delegate
    mapping(address => address) public delegates;

    /// @dev A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @dev A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @dev The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @dev The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @dev A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /// @dev An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @dev An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /// @dev The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev The standard EIP-20 approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    /**
     * @dev Construct a new Pxa token
     * @param _account Proxima Vault. All minted tokens are stored safely in vault
     */
    constructor(address _account) public {
        _totalSupply = safe96(
            10000000e18,
            "Pxa::_totalSupply: amount exceeds 96 bits"
        ); //10 million PXA
        balances[_account] = _totalSupply;
    }

    /**
     * @dev Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender)
        external
        view
        returns (uint256)
    {
        return allowances[account][spender];
    }

    /**
     * @dev Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 rawAmount)
        external
        returns (bool)
    {
        uint96 amount;
        if (rawAmount == uint256(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, "Pxa::approve: amount exceeds 96 bits");
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @dev Get current `totalSupply` of tokens
     * @return The number of tokens in circulation
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Get `supplyBurned` of tokens
     * @return The number of tokens burned till date
     */
    function totalBurned() external view returns (uint256) {
        return _supplyBurned;
    }

    /**
     * @dev Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 rawAmount) public returns (bool) {
        uint96 amount =
            safe96(rawAmount, "Pxa::transfer: amount exceeds 96 bits");
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @dev Burn `amount` tokens from `msg.sender`
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the burn succeeded
     */
    function burn(uint256 rawAmount) external returns (bool) {
        uint96 amount = safe96(rawAmount, "Pxa::burn: amount exceeds 96 bits");
        _burnTokens(msg.sender, amount);
        return true;
    }

    /**
     * @dev Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address src,
        address dst,
        uint256 rawAmount
    ) external returns (bool) {
        address spender = msg.sender;
        uint96 spenderAllowance = allowances[src][spender];
        uint96 amount =
            safe96(rawAmount, "Pxa::approve: amount exceeds 96 bits");

        if (spender != src && spenderAllowance != uint96(-1)) {
            uint96 newAllowance =
                sub96(
                    spenderAllowance,
                    amount,
                    "Pxa::transferFrom: transfer amount exceeds spender allowance"
                );
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator =
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes(name)),
                    getChainId(),
                    address(this)
                )
            );
        bytes32 structHash =
            keccak256(
                abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
            );
        bytes32 digest =
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "Pxa::delegateBySig: invalid signature"
        );
        require(
            nonce == nonces[signatory]++,
            "Pxa::delegateBySig: invalid nonce"
        );
        require(now <= expiry, "Pxa::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @dev Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return
            nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @dev Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        public
        view
        returns (uint96)
    {
        require(
            blockNumber < block.number,
            "Pxa::getPriorVotes: not yet determined"
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(
        address src,
        address dst,
        uint96 amount
    ) internal {
        require(
            src != address(0),
            "Pxa::_transferTokens: cannot transfer from the zero address"
        );
        require(
            dst != address(0),
            "Pxa::_transferTokens: cannot transfer to the zero address"
        );

        balances[src] = sub96(
            balances[src],
            amount,
            "Pxa::_transferTokens: transfer amount exceeds balance"
        );
        balances[dst] = add96(
            balances[dst],
            amount,
            "Pxa::_transferTokens: transfer amount overflows"
        );
        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _burnTokens(address src, uint96 amount) internal {
        balances[src] = sub96(
            balances[src],
            amount,
            "Pxa::_burn: burn amount exceeds balance"
        );
        _totalSupply = sub96(
            _totalSupply,
            amount,
            "Pxa::_burn: burn amount exceeds balance"
        );
        _supplyBurned = add96(
            _supplyBurned,
            amount,
            "Pxa::_burn: burn amount overflows"
        );
        emit Transfer(src, address(0), amount);
        
        _moveDelegates(delegates[src], delegates[address(0)], amount);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint96 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld =
                    srcRepNum > 0
                        ? checkpoints[srcRep][srcRepNum - 1].votes
                        : 0;
                uint96 srcRepNew =
                    sub96(
                        srcRepOld,
                        amount,
                        "Pxa::_moveVotes: vote amount underflows"
                    );
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld =
                    dstRepNum > 0
                        ? checkpoints[dstRep][dstRepNum - 1].votes
                        : 0;
                uint96 dstRepNew =
                    add96(
                        dstRepOld,
                        amount,
                        "Pxa::_moveVotes: vote amount overflows"
                    );
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint96 oldVotes,
        uint96 newVotes
    ) internal {
        uint32 blockNumber =
            safe32(
                block.number,
                "Pxa::_writeCheckpoint: block number exceeds 32 bits"
            );

        if (
            nCheckpoints > 0 &&
            checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber
        ) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(
                blockNumber,
                newVotes
            );
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint32)
    {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint96)
    {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
