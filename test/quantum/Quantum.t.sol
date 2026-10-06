// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/MockUSDT.sol";
import "../../src/quantum/QuantumGuard.sol";
import "../../src/quantum/QEscrowFactory.sol";
import "../../src/quantum/QEscrowInstance.sol";
import "../../src/quantum/QDisputeModule.sol";
import "../../script/lib/LamportSigner.sol";
import "../../script/lib/PQ.sol";

contract QuantumTest is Test {
    MockUSDT usdt;
    QuantumGuard guard;
    QDisputeModule dm;
    QEscrowFactory factory;

    address admin     = makeAddr("admin");
    address arbitro   = makeAddr("arbitro");
    address agente    = makeAddr("agente");
    address vendedor  = makeAddr("vendedor");
    address comprador = makeAddr("comprador");
    address treasury  = makeAddr("treasury");
    address atacante  = makeAddr("atacante");

    bytes32 constant SEMILLA_ADMIN    = keccak256("semilla-admin");
    bytes32 constant SEMILLA_AGENTE   = keccak256("semilla-agente");
    bytes32 constant SEMILLA_ARBITRO  = keccak256("semilla-arbitro");
    bytes32 constant SEMILLA_VENDEDOR = keccak256("semilla-vendedor");

    uint256 constant MONTO   = 200e6;
    uint256 constant FEE_BPS = 500;

    function setUp() public {
        usdt    = new MockUSDT();
        guard   = new QuantumGuard(admin);
        dm      = new QDisputeModule(admin, address(guard), arbitro);
        factory = new QEscrowFactory(admin, address(guard), address(usdt), address(dm), treasury, FEE_BPS, agente);

        address[] memory cs = new address[](2);
        cs[0] = address(factory);
        cs[1] = address(dm);
        guard.inicializar(address(factory), cs);

        _registrar(admin,   SEMILLA_ADMIN);
        _registrar(agente,  SEMILLA_AGENTE);
        _registrar(arbitro, SEMILLA_ARBITRO);

        usdt.mint(vendedor, 10_000e6);
        vm.prank(vendedor);
        usdt.approve(address(factory), type(uint256).max);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    function _registrar(address quien, bytes32 semilla) internal {
        vm.prank(quien);
        guard.registrarClave(LamportSigner.pkHash(semilla, 0));
    }

    function _firma(bytes32 semilla, address consumidor, address firmante, bytes32 accion)
        internal view returns (bytes memory)
    {
        return PQ.firma(guard, semilla, consumidor, firmante, accion);
    }

    function _crear(bytes32 ref) internal returns (QEscrowInstance) {
        vm.prank(vendedor);
        return QEscrowInstance(factory.crearOrden(comprador, MONTO, ref, 30 minutes));
    }

    function _activar(QEscrowInstance inst) internal {
        bytes memory f = _firma(SEMILLA_AGENTE, address(inst), agente, inst.ACCION_ACTIVAR());
        vm.prank(agente);
        inst.activarEscrow(f);
    }

    function _crearYActivar(bytes32 ref) internal returns (QEscrowInstance inst) {
        inst = _crear(ref);
        _activar(inst);
    }

    // ─── Lamport ──────────────────────────────────────────────────────────

    function test_lamport_firma_valida() public pure {
        bytes32 semilla = keccak256("x");
        bytes32 d = keccak256("mensaje");
        (bytes32[256] memory r, bytes32[256] memory o) = LamportSigner.firmar(semilla, 0, d);
        assertTrue(Lamport.verificar(d, LamportSigner.pkHash(semilla, 0), r, o));
    }

    function testFuzz_lamport_rechaza_otro_mensaje(bytes32 d, bytes32 otro) public pure {
        vm.assume(d != otro);
        bytes32 semilla = keccak256("x");
        (bytes32[256] memory r, bytes32[256] memory o) = LamportSigner.firmar(semilla, 0, d);
        assertFalse(Lamport.verificar(otro, LamportSigner.pkHash(semilla, 0), r, o));
    }

    function test_lamport_rechaza_clave_cero() public pure {
        bytes32 d = keccak256("m");
        (bytes32[256] memory r, bytes32[256] memory o) = LamportSigner.firmar(keccak256("x"), 0, d);
        assertFalse(Lamport.verificar(d, bytes32(0), r, o));
    }

    // ─── Guard ────────────────────────────────────────────────────────────

    function test_inicializar_solo_una_vez() public {
        address[] memory cs = new address[](0);
        vm.expectRevert("ya inicializado");
        guard.inicializar(address(0), cs);
    }

    function test_registrar_clave_solo_una_vez() public {
        vm.prank(agente);
        vm.expectRevert("clave ya registrada");
        guard.registrarClave(keccak256("otra"));
    }

    function test_consumidor_no_autorizado() public {
        bytes memory f = _firma(SEMILLA_AGENTE, atacante, agente, keccak256("x"));
        vm.prank(atacante);
        vm.expectRevert("consumidor no autorizado");
        guard.consumir(agente, keccak256("x"), f);
    }

    function test_rotar_clave() public {
        bytes32 antes = guard.clavePQ(agente);
        bytes memory f = _firma(SEMILLA_AGENTE, address(guard), agente, guard.ACCION_ROTAR());
        vm.prank(agente);
        guard.rotarClave(f);
        assertEq(guard.nonces(agente), 1);
        assertEq(guard.clavePQ(agente), LamportSigner.pkHash(SEMILLA_AGENTE, 1));
        assertTrue(guard.clavePQ(agente) != antes);
    }

    function test_admin_guard_requiere_pq() public {
        bytes memory f = _firma(SEMILLA_ADMIN, address(guard), admin, keccak256(abi.encode("SET_CONSUMIDOR", atacante, true)));
        vm.prank(atacante);
        vm.expectRevert("solo admin");
        guard.setConsumidor(atacante, true, f);

        vm.prank(admin);
        vm.expectRevert("firma PQ requerida");
        guard.setConsumidor(atacante, true, "");

        vm.prank(admin);
        guard.setConsumidor(atacante, true, f);
        assertTrue(guard.consumidores(atacante));
    }

    // ─── Flujo de escrow ──────────────────────────────────────────────────

    function test_flujo_completo_liberacion_agente() public {
        QEscrowInstance inst = _crearYActivar(keccak256("ord-1"));

        bytes memory f = _firma(SEMILLA_AGENTE, address(inst), agente, inst.ACCION_LIBERAR());
        vm.prank(agente);
        inst.liberarEscrowPQ(f);

        uint256 fee = (MONTO * FEE_BPS) / 10000;
        assertEq(usdt.balanceOf(comprador), MONTO - fee);
        assertEq(usdt.balanceOf(treasury),  fee);
        assertEq(uint(inst.estado()), uint(QEscrowInstance.Estado.COMPLETADA));
        assertEq(guard.nonces(agente), 2);
    }

    function test_vendedor_sin_clave_libera_con_wallet() public {
        QEscrowInstance inst = _crearYActivar(keccak256("ord-2"));
        vm.prank(vendedor);
        inst.liberarEscrow();
        assertEq(uint(inst.estado()), uint(QEscrowInstance.Estado.COMPLETADA));
    }

    function test_agente_no_puede_liberar_sin_pq() public {
        QEscrowInstance inst = _crearYActivar(keccak256("ord-3"));
        vm.prank(agente);
        vm.expectRevert("firma PQ requerida");
        inst.liberarEscrow();
    }

    function test_agente_ecdsa_comprometido_no_basta() public {
        // Simula un atacante que rompió la clave ECDSA del agente (p. ej. con
        // un computador cuántico) pero no conoce la semilla Lamport.
        QEscrowInstance inst = _crear(keccak256("ord-4"));
        bytes memory falsa = PQ.firma(guard, keccak256("semilla-falsa"), address(inst), agente, inst.ACCION_ACTIVAR());
        vm.prank(agente);
        vm.expectRevert("firma PQ invalida");
        inst.activarEscrow(falsa);
    }

    function test_firma_no_reutilizable_entre_instancias() public {
        QEscrowInstance a = _crear(keccak256("ord-5a"));
        QEscrowInstance b = _crear(keccak256("ord-5b"));
        bytes memory f = _firma(SEMILLA_AGENTE, address(a), agente, a.ACCION_ACTIVAR());

        vm.prank(agente);
        vm.expectRevert("firma PQ invalida");
        b.activarEscrow(f);

        vm.prank(agente);
        a.activarEscrow(f);

        // Replay en la misma instancia tampoco: la clave ya rotó.
        assertEq(uint(a.estado()), uint(QEscrowInstance.Estado.ACTIVA));
    }

    function test_firma_no_reutilizable_tras_rotacion() public {
        QEscrowInstance a = _crear(keccak256("ord-6"));
        bytes memory f = _firma(SEMILLA_AGENTE, address(a), agente, a.ACCION_ACTIVAR());
        vm.prank(agente);
        a.activarEscrow(f);

        bytes memory f2 = _firma(SEMILLA_AGENTE, address(a), agente, a.ACCION_LIBERAR());
        // Reusar la firma de activación falla: su clave ya fue consumida.
        vm.prank(agente);
        vm.expectRevert("siguiente clave invalida");
        a.liberarEscrowPQ(f);

        vm.prank(agente);
        a.liberarEscrowPQ(f2);
    }

    function test_expiracion_con_pq() public {
        QEscrowInstance inst = _crearYActivar(keccak256("ord-7"));
        uint256 balAntes = usdt.balanceOf(vendedor);
        vm.warp(block.timestamp + 31 minutes);

        bytes memory f = _firma(SEMILLA_AGENTE, address(inst), agente, inst.ACCION_EXPIRAR());
        vm.prank(agente);
        inst.expirarOrden(f);
        assertEq(usdt.balanceOf(vendedor), balAntes + MONTO);
    }

    function test_vendedor_con_clave_debe_usar_pq() public {
        _registrar(vendedor, SEMILLA_VENDEDOR);

        vm.prank(vendedor);
        vm.expectRevert("firma PQ requerida");
        factory.crearOrden(comprador, MONTO, keccak256("ord-8"), 30 minutes);

        bytes32 accion = factory.accionCrearOrden(comprador, MONTO, keccak256("ord-8"), 30 minutes);
        bytes memory f = _firma(SEMILLA_VENDEDOR, address(factory), vendedor, accion);
        vm.prank(vendedor);
        QEscrowInstance inst = QEscrowInstance(
            factory.crearOrdenPQ(comprador, MONTO, keccak256("ord-8"), 30 minutes, f)
        );
        _activar(inst);

        vm.prank(vendedor);
        vm.expectRevert("firma PQ requerida");
        inst.liberarEscrow();

        bytes memory f2 = _firma(SEMILLA_VENDEDOR, address(inst), vendedor, inst.ACCION_LIBERAR());
        vm.prank(vendedor);
        inst.liberarEscrowPQ(f2);
        assertEq(uint(inst.estado()), uint(QEscrowInstance.Estado.COMPLETADA));
    }

    // ─── Disputas ─────────────────────────────────────────────────────────

    function test_disputa_comprador_y_arbitro_pq() public {
        QEscrowInstance inst = _crearYActivar(keccak256("ord-9"));
        vm.prank(comprador);
        inst.abrirDisputa();

        vm.prank(comprador);
        dm.registrarVoto(address(inst), comprador);

        vm.prank(arbitro);
        vm.expectRevert("firma PQ requerida");
        dm.registrarVoto(address(inst), comprador);

        bytes memory f = _firma(SEMILLA_ARBITRO, address(dm), arbitro, dm.accionVoto(address(inst), comprador));
        vm.prank(arbitro);
        dm.registrarVotoPQ(address(inst), comprador, f);

        assertEq(usdt.balanceOf(comprador), MONTO);
        assertEq(uint(inst.estado()), uint(QEscrowInstance.Estado.RESUELTA));
    }

    function test_firma_arbitro_ligada_al_ganador() public {
        QEscrowInstance inst = _crearYActivar(keccak256("ord-10"));
        vm.prank(vendedor);
        inst.abrirDisputa();

        bytes memory f = _firma(SEMILLA_ARBITRO, address(dm), arbitro, dm.accionVoto(address(inst), comprador));
        vm.prank(arbitro);
        vm.expectRevert("firma PQ invalida");
        dm.registrarVotoPQ(address(inst), vendedor, f);
    }

    // ─── Administración ───────────────────────────────────────────────────

    function test_set_fee_requiere_pq_admin() public {
        vm.prank(admin);
        vm.expectRevert("firma PQ requerida");
        factory.setFeeBps(100, "");

        bytes memory f = _firma(SEMILLA_ADMIN, address(factory), admin, keccak256(abi.encode("SET_FEE", uint256(100))));
        vm.prank(admin);
        factory.setFeeBps(100, f);
        assertEq(factory.feeBps(), 100);
    }

    function test_set_arbitro_requiere_pq_admin() public {
        address nuevo = makeAddr("nuevo-arbitro");
        bytes memory f = _firma(SEMILLA_ADMIN, address(dm), admin, keccak256(abi.encode("SET_ARBITRO", nuevo, true)));
        vm.prank(admin);
        dm.setArbitro(nuevo, true, f);
        assertTrue(dm.esArbitro(nuevo));
    }

    function test_gas_activacion_pq() public {
        QEscrowInstance inst = _crear(keccak256("ord-gas"));
        bytes memory f = _firma(SEMILLA_AGENTE, address(inst), agente, inst.ACCION_ACTIVAR());
        vm.prank(agente);
        uint256 g = gasleft();
        inst.activarEscrow(f);
        emit log_named_uint("gas activarEscrow (PQ)", g - gasleft());
    }
}
