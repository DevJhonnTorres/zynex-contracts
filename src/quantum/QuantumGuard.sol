// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Lamport.sol";

interface IFactoryInstancias {
    function esInstanciaValida(address instancia) external view returns (bool);
}

/// @title QuantumGuard
/// @notice Registro de claves post-cuánticas (Lamport) y verificador de firmas
///         para los contratos P2P de Zynex.
/// @dev Modelo híbrido: cada acción protegida exige la firma ECDSA de la
///      transacción (msg.sender) Y una firma Lamport válida del mismo firmante.
///      Cada firma consume la clave actual y registra la siguiente (rotación
///      obligatoria), así ninguna clave Lamport se usa dos veces.
///
///      El digest firmado incluye chainid, este contrato, el contrato
///      consumidor, el firmante, su nonce, la acción y la siguiente clave, de
///      modo que una firma no puede reutilizarse en otro contexto.
contract QuantumGuard {
    bytes32 public constant DOMINIO = keccak256("ZYNEX_QUANTUM_GUARD_V1");
    uint256 public constant LARGO_FIRMA = 32 * (1 + 2 * Lamport.BITS);

    bytes32 public constant ACCION_ROTAR = keccak256("ROTAR_CLAVE");

    address public admin;
    address public immutable desplegador;
    bool public inicializado;

    /// @notice Factory cuyas instancias válidas pueden consumir firmas.
    address public factory;
    mapping(address => bool) public consumidores;

    mapping(address => bytes32) public clavePQ;
    mapping(address => uint256) public nonces;

    event ClaveRegistrada(address indexed firmante, bytes32 pkHash);
    event ClaveRotada(address indexed firmante, uint256 indexed nonce, bytes32 nuevoPkHash);
    event FirmaConsumida(address indexed consumidor, address indexed firmante, bytes32 indexed accion, uint256 nonce);
    event ConsumidorActualizado(address indexed consumidor, bool habilitado);
    event FactoryActualizada(address indexed factory);
    event AdminTransferido(address indexed nuevoAdmin);

    constructor(address admin_) {
        require(admin_ != address(0), "admin invalido");
        admin       = admin_;
        desplegador = msg.sender;
    }

    /// @notice Configuración inicial única (antes de que existan claves PQ del admin).
    function inicializar(address factory_, address[] calldata consumidores_) external {
        require(msg.sender == desplegador, "solo desplegador");
        require(!inicializado, "ya inicializado");
        inicializado = true;

        factory = factory_;
        emit FactoryActualizada(factory_);
        for (uint256 i; i < consumidores_.length; ++i) {
            consumidores[consumidores_[i]] = true;
            emit ConsumidorActualizado(consumidores_[i], true);
        }
    }

    // ─── Claves ────────────────────────────────────────────────────────────

    /// @notice Registra la primera clave PQ de msg.sender. Las siguientes solo
    ///         pueden cambiarse con una firma PQ válida (rotación).
    function registrarClave(bytes32 pkHash) external {
        require(pkHash != bytes32(0), "clave invalida");
        require(clavePQ[msg.sender] == bytes32(0), "clave ya registrada");
        clavePQ[msg.sender] = pkHash;
        emit ClaveRegistrada(msg.sender, pkHash);
    }

    /// @notice Rota la clave PQ de msg.sender sin ejecutar ninguna otra acción.
    function rotarClave(bytes calldata firma) external {
        _consumir(address(this), msg.sender, ACCION_ROTAR, firma);
    }

    function tieneClave(address firmante) external view returns (bool) {
        return clavePQ[firmante] != bytes32(0);
    }

    // ─── Verificación ─────────────────────────────────────────────────────

    /// @notice Digest que `firmante` debe firmar con su clave Lamport actual.
    function digest(
        address consumidor,
        address firmante,
        bytes32 accion,
        bytes32 siguientePkHash
    ) public view returns (bytes32) {
        return keccak256(abi.encode(
            DOMINIO,
            block.chainid,
            address(this),
            consumidor,
            firmante,
            nonces[firmante],
            accion,
            siguientePkHash
        ));
    }

    function esConsumidor(address c) public view returns (bool) {
        if (consumidores[c]) return true;
        address f = factory;
        return f != address(0) && IFactoryInstancias(f).esInstanciaValida(c);
    }

    /// @notice Verifica y consume una firma PQ de `firmante` para `accion`.
    /// @dev Solo contratos consumidores autorizados: evita que terceros quemen
    ///      una firma publicada en el mempool antes de que llegue a su destino.
    function consumir(address firmante, bytes32 accion, bytes calldata firma) external {
        require(esConsumidor(msg.sender), "consumidor no autorizado");
        _consumir(msg.sender, firmante, accion, firma);
    }

    function _consumir(address consumidor, address firmante, bytes32 accion, bytes calldata firma) internal {
        bytes32 actual = clavePQ[firmante];
        require(actual != bytes32(0), "sin clave PQ");
        require(firma.length == LARGO_FIRMA, "firma PQ requerida");

        (bytes32 siguiente, bytes32[256] memory revelados, bytes32[256] memory opuestos) =
            abi.decode(firma, (bytes32, bytes32[256], bytes32[256]));
        require(siguiente != bytes32(0) && siguiente != actual, "siguiente clave invalida");

        bytes32 d = digest(consumidor, firmante, accion, siguiente);
        require(Lamport.verificar(d, actual, revelados, opuestos), "firma PQ invalida");

        uint256 n = nonces[firmante]++;
        clavePQ[firmante] = siguiente;

        emit FirmaConsumida(consumidor, firmante, accion, n);
        emit ClaveRotada(firmante, n + 1, siguiente);
    }

    // ─── Administración (protegida por PQ) ────────────────────────────────

    modifier soloAdminPQ(bytes32 accion, bytes calldata firma) {
        require(msg.sender == admin, "solo admin");
        _consumir(address(this), admin, accion, firma);
        _;
    }

    function setConsumidor(address c, bool habilitado, bytes calldata firma)
        external
        soloAdminPQ(keccak256(abi.encode("SET_CONSUMIDOR", c, habilitado)), firma)
    {
        consumidores[c] = habilitado;
        emit ConsumidorActualizado(c, habilitado);
    }

    function setFactory(address f, bytes calldata firma)
        external
        soloAdminPQ(keccak256(abi.encode("SET_FACTORY", f)), firma)
    {
        factory = f;
        emit FactoryActualizada(f);
    }

    function transferirAdmin(address nuevo, bytes calldata firma)
        external
        soloAdminPQ(keccak256(abi.encode("TRANSFERIR_ADMIN", nuevo)), firma)
    {
        require(nuevo != address(0), "admin invalido");
        admin = nuevo;
        emit AdminTransferido(nuevo);
    }
}
