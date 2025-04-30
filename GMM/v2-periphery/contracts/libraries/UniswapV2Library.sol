pragma solidity >=0.5.0;

import "../../../v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex"026e50af527b3edc71e949a5831a54eb94609fa180e0eb4427ee379a3e7bc500" // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, address tokenOut, address pair, address[] memory other) internal view returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 reserveIn_all = 0;
        uint256 reserveOut_all = 0;
        {
            uint256 reserveIn_all_aux = 0;
            uint256 reserveOut_all_aux = 0;

            for (uint i = 0; i < other.length; i++){
                if (tokenOut == IUniswapV2Pair(pair).token0())
                    (reserveOut_all_aux, reserveIn_all_aux, ) = IUniswapV2Pair(other[i]).getReserves();
                else
                    (reserveIn_all_aux, reserveOut_all_aux, ) = IUniswapV2Pair(other[i]).getReserves();
                reserveIn_all = reserveIn_all.add(reserveIn_all_aux);
                reserveOut_all = reserveOut_all.add(reserveOut_all_aux);
            }
        }
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        uint numerator_all = amountInWithFee.mul(reserveOut_all);
        uint denominator_all = reserveIn_all.mul(1000).add(amountInWithFee);
        
        uint amountOut_original = (numerator / denominator);
        uint amountOut_all = (numerator_all / denominator_all);
        amountOut = amountOut_original < amountOut_all ? amountOut_original : amountOut_all;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, address tokenOut, address pair, address[] memory other) internal view returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 reserveIn_all = 0;
        uint256 reserveOut_all = 0;
        {
            uint256 reserveIn_all_aux = 0;
            uint256 reserveOut_all_aux = 0;

            for (uint i = 0; i < other.length; i++){
                if (tokenOut == IUniswapV2Pair(pair).token0())
                    (reserveOut_all_aux, reserveIn_all_aux, ) = IUniswapV2Pair(other[i]).getReserves();
                else
                    (reserveIn_all_aux, reserveOut_all_aux, ) = IUniswapV2Pair(other[i]).getReserves();
                reserveIn_all = reserveIn_all.add(reserveIn_all_aux);
                reserveOut_all = reserveOut_all.add(reserveOut_all_aux);
            }
        }
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        uint numerator_all = reserveIn_all.mul(amountOut).mul(1000);
        uint denominator_all = reserveOut_all.sub(amountOut).mul(997);

        uint amountIn_original = (numerator / denominator).add(1);
        uint amountIn_all = (numerator_all / denominator_all).add(1);
        amountIn = amountIn_original < amountIn_all ? amountIn_original : amountIn_all;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            address pair = pairFor(factory, path[i], path[i + 1]);
            address[] memory other = IUniswapV2Pair(pair).getOtherAmm();
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, path[i + 1], pair, other);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            address pair = pairFor(factory, path[0], path[1]);
            address[] memory other = IUniswapV2Pair(pair).getOtherAmm();
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, path[i], pair, other);
        }
    }
}
