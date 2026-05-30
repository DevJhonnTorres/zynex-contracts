// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DisputeModule.sol";

contract MockEscrowInstance {
    address public ganadorResolucion;
    DisputeModule public dm;
    address public comprador;
    address public vendedor;

    constructor(address comprador_, address vendedor_, DisputeModule dm_) {
        comprador = comprador_;
        vendedor  = vendedor_;
        dm        = dm_;
    }

    function abrirDisputaEnModulo() external {
        dm.registrarDisputa(comprador, vendedor);
    }

    function ejecutarResolucion(address ganador) external {
        ganadorResolucion = ganador;
    }
}

contract DisputeModuleTest is Test {
    DisputeModule dm;
    address admin     = makeAddr("admin");
    address arbitro   = makeAddr("arbitro");
    address comprador = makeAddr("comprador");
    address vendedor  = makeAddr("vendedor");
    MockEscrowInstance instancia;

    function setUp() public {
        dm       = new DisputeModule(admin, arbitro);
        instancia = new MockEscrowInstance(comprador, vendedor, dm);
    }

    function test_arbitro_tiene_role() public view {
        assertTrue(dm.hasRole(dm.ARBITRO_ROLE(), arbitro));
    }

    function test_registrar_disputa() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);
        (address c, address v,,, bool r) = dm.getDisputa(address(instancia));
        assertEq(c, comprador);
        assertEq(v, vendedor);
        assertFalse(r);
    }

    function test_no_doble_registro() public {
        vm.startPrank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);
        vm.expectRevert("disputa ya registrada");
        dm.registrarDisputa(comprador, vendedor);
        vm.stopPrank();
    }

    function test_voto_comprador_registrado() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.prank(comprador);
        dm.registrarVoto(address(instancia), comprador);

        (,, uint8 votosC,,) = dm.getDisputa(address(instancia));
        assertEq(votosC, 1);
    }

    function test_1_voto_no_resuelve() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.prank(comprador);
        dm.registrarVoto(address(instancia), comprador);

        assertEq(instancia.ganadorResolucion(), address(0));
    }

    function test_resolucion_2de3_comprador_gana() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.prank(comprador);
        dm.registrarVoto(address(instancia), comprador);
        vm.prank(arbitro);
        dm.registrarVoto(address(instancia), comprador);

        assertEq(instancia.ganadorResolucion(), comprador);
        (,,,, bool r) = dm.getDisputa(address(instancia));
        assertTrue(r);
    }

    function test_resolucion_2de3_vendedor_gana() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.prank(vendedor);
        dm.registrarVoto(address(instancia), vendedor);
        vm.prank(arbitro);
        dm.registrarVoto(address(instancia), vendedor);

        assertEq(instancia.ganadorResolucion(), vendedor);
    }

    function test_no_doble_voto() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.startPrank(comprador);
        dm.registrarVoto(address(instancia), comprador);
        vm.expectRevert("ya voto");
        dm.registrarVoto(address(instancia), comprador);
        vm.stopPrank();
    }

    function test_no_voto_no_autorizado() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.prank(makeAddr("extrano"));
        vm.expectRevert("no autorizado");
        dm.registrarVoto(address(instancia), comprador);
    }

    function test_ganador_invalido() public {
        vm.prank(address(instancia));
        dm.registrarDisputa(comprador, vendedor);

        vm.prank(comprador);
        vm.expectRevert("ganador invalido");
        dm.registrarVoto(address(instancia), makeAddr("tercero"));
    }
}
