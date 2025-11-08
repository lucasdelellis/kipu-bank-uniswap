
🏦 KipuBank Smart Contract
📖 Descripción General

KipuBank es un contrato inteligente en Solidity que implementa un sistema bancario simple y seguro sobre la red Ethereum.
Los usuarios pueden depositar y retirar tanto ETH como USDC, manteniendo balances individuales dentro del contrato.
El valor total del banco se controla en USD, utilizando Chainlink Price Feeds para conversión automática de precios.

El objetivo del contrato es simular una infraestructura bancaria que permita manejar múltiples activos de forma segura, aplicando límites de depósito, retiro y cap total.
🚀 Mejoras Realizadas y Motivación

Esta versión de KipuBank introduce una serie de mejoras estructurales y de seguridad respecto a la versión original:
🔹 Soporte Multi-token (ETH y USDC)

    Se agregó soporte para múltiples tokens utilizando el mapping doble:

    mapping(address user => mapping(address token => uint256 balance))

      Permite manejar balances separados por token sin necesidad de contratos duplicados.

🔹 Integración con Chainlink Price Feeds

Se incorporaron los feeds de ETH/USD y USDC/USD:

AggregatorV3Interface public s_feedETHToUSD;
AggregatorV3Interface public s_feedUSDCToUSD;

El contrato convierte automáticamente cualquier depósito o retiro a su equivalente en USD.

Esto permite aplicar límites y caps unificados en USD, sin depender de la volatilidad de los activos.

🔹 Seguridad y Confiabilidad

Uso de SafeERC20 para todas las transferencias de tokens ERC20, evitando pérdidas por tokens no estándar.

Implementación del patrón Checks-Effects-Interactions y protección con ReentrancyGuard.

Validaciones de oráculo:

    Verificación de precio no nulo.

    Verificación de datos con ORACLE_HEARTBEAT (1 hora).

    Reversiones claras con errores específicos (KipuBank_OracleCompromised, KipuBank_StalePrice).

🔹 Auditoría y Control

Eventos detallados para cada operación:

    KipuBank_DepositReceived

    KipuBank_WithdrawalMade

    KipuBank_ChainlinkEthToUsdFeedUpdated

    KipuBank_ChainlinkUsdcToUsdFeedUpdated

Contadores globales de depósitos (s_depositCount) y retiros (s_withdrawalCount).

🔹 Límites y Caps

i_bankCap: límite máximo de USD que el contrato puede almacenar.

i_maxWithdrawal: límite máximo de USD que un usuario puede retirar por transacción.

⚙️ Variables de despliegue

_bankCap // Cap total del contrato en USD (ej: 100_000 * 1e8) _maxWithdrawal // Monto máximo de retiro en USD por transacción (ej: 1_000 * 1e8) _owner // Dirección del propietario del contrato _feedETHToUSD // Dirección del feed de Chainlink ETH/USD _usdc // Dirección del token USDC (ERC20) _feedUSDCToUSD // Dirección del feed de Chainlink USDC/USD

🧩 Interacción con el Contrato
Depositar ETH

function depositETH() external payable

O directamente enviando ETH al contrato (activará receive()).
Depositar USDC

function depositUSDC(uint256 amount) external

Antes de llamar, el usuario debe aprobar al contrato para mover sus USDC:

usdc.approve(address(kipuBank), amount); kipuBank.depositUSDC(amount);
Retirar ETH o USDC

function withdrawETH(uint256 amount) external function withdrawUSDC(uint256 amount) external

El retiro se valida en USD y debe cumplir:

No superar el límite i_maxWithdrawal

No superar el balance del usuario

Consultar balance

function getBalance() external view returns (uint256)

Retorna el balance del usuario en USD, combinando ETH y USDC.
Cambiar feeds de Chainlink (solo Owner)

function setETHToUSDFeed(address newFeed) external onlyOwner function setUSDCToUSDFeed(address newFeed) external onlyOwner

🧠 Decisiones de Diseño y Trade-offs ✅ Diseño basado en USD

Se decidió unificar todos los límites y balances internos en USD para simplificar la gestión multi-token.

Esto implica dependencia en oráculos Chainlink, pero permite una capa de abstracción estable frente a volatilidad.

⚖️ Trade-off: precisión vs. simplicidad

Los precios de Chainlink y los decimales de los tokens se normalizan a 18 y 6 respectivamente.

Aunque puede generar pequeñas diferencias por rounding, simplifica los cálculos y evita overflow.

🔒 Seguridad por diseño

ReentrancyGuard evita ataques por múltiples llamadas en la misma transacción.

SafeERC20 asegura compatibilidad con tokens ERC20 no estándar.

Las funciones privadas siguen el patrón Checks → Effects → Interactions.

🧩 Escalabilidad

El uso de mapping(address => mapping(address => uint256)) permite extender fácilmente el soporte a más tokens ERC20 en el futuro.

📜 Licencia

Este proyecto está licenciado bajo MIT License.

🔗 Contrato en Etherscan

    Etherscan link

