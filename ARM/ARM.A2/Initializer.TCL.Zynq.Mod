MODULE ZynqInitializer;

IMPORT SYSTEM;

	(** Performs hardware initialization, initial stack setup and interrupt vector setup *)
	PROCEDURE {INITIAL} Init;
	CODE
		; interrupt vectors at address 0
		RESET: 	ldr pc, [pc, #reset-$-8]; 			RESET
		UNDEF: 	ldr pc, [pc, #undef-$-8]; 			UNDEF
		SWI: 		ldr pc, [pc, #swi-$-8]; 				SWI
		PREF: 		ldr pc, [pc, #prefetch-$-8]; 			Prefetch Abort
		DATA: 		ldr pc, [pc, #data-$-8]; 				Data Abort
		INVALID: 	B INVALID ; 					(not assigned)
		IRQ: 		ldr pc, [pc, #irq-$-8]; 					IRQ
		FIQ: 		ldr pc, [pc, #fiq-$-8]; 					FIQ

		; initial interrupt vector setup such that inifinte loop is triggered
		reset: 		d32 init
		undef: 		d32 UNDEF
		swi: 		d32 SWI
		prefetch: 	d32 PREF
		data: 		d32 DATA
		empty:		d32 0
		irq: 		d32 IRQ
		fiq: 		d32 FIQ

		init:
		; let only processor 0 through
			mrc	p15,0,r1,c0,c0,5
			and	r1, r1, #0xf
			cmp	r1, #0
			beq	OKToRun

		EndlessLoop0:
			d32 0b11100011001000001111000000000010 ;WFE
			B	EndlessLoop0

		OKToRun:
			; call initialization script as provided by Xilinx Tools
			ldr FP, [pc, #InitialFP-$-8] ; set stack pointer
			ldr SP, [pc, #InitialFP-$-8] ; set frame pointer
			bl InitializeHW

		loop:
			b loop

		; constants used
		InitialFP: 			d32 00030000H ; initial frame pointer address, internal memory bank
	END Init;

	CONST

	(* the following initialization sequences have been inferred from ps7_init.tcl and ps7_init.c for the Zynq board *)

	mask_write = 0;
	mask_poll = 1;

ps7_pll_init_data = [
    mask_write ,0xF8000008 ,0x0000FFFF ,0x0000DF0D
    ,mask_write ,0xF8000110 ,0x003FFFF0 ,0x000FA220
    ,mask_write ,0xF8000100 ,0x0007F000 ,0x00028000
    ,mask_write ,0xF8000100 ,0x00000010 ,0x00000010
    ,mask_write ,0xF8000100 ,0x00000001 ,0x00000001
    ,mask_write ,0xF8000100 ,0x00000001 ,0x00000000
    ,mask_poll ,0xF800010C ,0x00000001
    ,mask_write ,0xF8000100 ,0x00000010 ,0x00000000
    ,mask_write ,0xF8000120 ,0x1F003F30 ,0x1F000200
    ,mask_write ,0xF8000114 ,0x003FFFF0 ,0x0012C220
    ,mask_write ,0xF8000104 ,0x0007F000 ,0x00020000
    ,mask_write ,0xF8000104 ,0x00000010 ,0x00000010
    ,mask_write ,0xF8000104 ,0x00000001 ,0x00000001
    ,mask_write ,0xF8000104 ,0x00000001 ,0x00000000
    ,mask_poll ,0xF800010C ,0x00000002
    ,mask_write ,0xF8000104 ,0x00000010 ,0x00000000
    ,mask_write ,0xF8000124 ,0xFFF00003 ,0x0C200003
    ,mask_write ,0xF8000118 ,0x003FFFF0 ,0x001452C0
    ,mask_write ,0xF8000108 ,0x0007F000 ,0x0001E000
    ,mask_write ,0xF8000108 ,0x00000010 ,0x00000010
    ,mask_write ,0xF8000108 ,0x00000001 ,0x00000001
    ,mask_write ,0xF8000108 ,0x00000001 ,0x00000000
    ,mask_poll ,0xF800010C ,0x00000004
    ,mask_write ,0xF8000108 ,0x00000010 ,0x00000000
    ,mask_write ,0xF8000004 ,0x0000FFFF ,0x0000767B
];

ps7_clock_init_data=[
    mask_write ,0xF8000008 ,0x0000FFFF ,0x0000DF0D
    ,mask_write ,0xF8000128 ,0x03F03F01 ,0x00302301
    ,mask_write ,0xF8000138 ,0x00000011 ,0x00000001
    ,mask_write ,0xF8000140 ,0x03F03F71 ,0x00100801
    ,mask_write ,0xF800014C ,0x00003F31 ,0x00000721
    ,mask_write ,0xF8000150 ,0x00003F33 ,0x00001401
    ,mask_write ,0xF8000154 ,0x00003F33 ,0x00001402
    ,mask_write ,0xF8000168 ,0x00003F31 ,0x00000501
    ,mask_write ,0xF8000170 ,0x03F03F30 ,0x00100A00
    ,mask_write ,0xF8000180 ,0x03F03F30 ,0x00100700
    ,mask_write ,0xF8000190 ,0x03F03F30 ,0x00101400
    ,mask_write ,0xF80001A0 ,0x03F03F30 ,0x00101400
    ,mask_write ,0xF80001C4 ,0x00000001 ,0x00000001
    ,mask_write ,0xF800012C ,0x01FFCCCD ,0x01EC044D
    ,mask_write ,0xF8000004 ,0x0000FFFF ,0x0000767B
]; 

ps7_ddr_init_data =[
    mask_write ,0xF8006000 ,0x0001FFFF ,0x00000080
    ,mask_write ,0xF8006004 ,0x1FFFFFFF ,0x00081081
    ,mask_write ,0xF8006008 ,0x03FFFFFF ,0x03C0780F
    ,mask_write ,0xF800600C ,0x03FFFFFF ,0x02001001
    ,mask_write ,0xF8006010 ,0x03FFFFFF ,0x00014001
    ,mask_write ,0xF8006014 ,0x001FFFFF ,0x0004159B
    ,mask_write ,0xF8006018 ,0xF7FFFFFF ,0x452460D2
    ,mask_write ,0xF800601C ,0xFFFFFFFF ,0x720238E5
    ,mask_write ,0xF8006020 ,0xFFFFFFFC ,0x272872D0
    ,mask_write ,0xF8006024 ,0x0FFFFFFF ,0x0000003C
    ,mask_write ,0xF8006028 ,0x00003FFF ,0x00002007
    ,mask_write ,0xF800602C ,0xFFFFFFFF ,0x00000008
    ,mask_write ,0xF8006030 ,0xFFFFFFFF ,0x00040930
    ,mask_write ,0xF8006034 ,0x13FF3FFF ,0x00010694
    ,mask_write ,0xF8006038 ,0x00001FC3 ,0x00000000
    ,mask_write ,0xF800603C ,0x000FFFFF ,0x00000777
    ,mask_write ,0xF8006040 ,0xFFFFFFFF ,0xFFF00000
    ,mask_write ,0xF8006044 ,0x0FFFFFFF ,0x0FF66666
    ,mask_write ,0xF8006048 ,0x3FFFFFFF ,0x0003C248
    ,mask_write ,0xF8006050 ,0xFF0F8FFF ,0x77010800
    ,mask_write ,0xF8006058 ,0x0001FFFF ,0x00000101
    ,mask_write ,0xF800605C ,0x0000FFFF ,0x00005003
    ,mask_write ,0xF8006060 ,0x000017FF ,0x0000003E
    ,mask_write ,0xF8006064 ,0x00021FE0 ,0x00020000
    ,mask_write ,0xF8006068 ,0x03FFFFFF ,0x00284141
    ,mask_write ,0xF800606C ,0x0000FFFF ,0x00001610
    ,mask_write ,0xF80060A0 ,0x00FFFFFF ,0x00008000
    ,mask_write ,0xF80060A4 ,0xFFFFFFFF ,0x10200802
    ,mask_write ,0xF80060A8 ,0x0FFFFFFF ,0x0690CB73
    ,mask_write ,0xF80060AC ,0x000001FF ,0x000001FE
    ,mask_write ,0xF80060B0 ,0x1FFFFFFF ,0x1CFFFFFF
    ,mask_write ,0xF80060B4 ,0x000007FF ,0x00000200
    ,mask_write ,0xF80060B8 ,0x01FFFFFF ,0x00200066
    ,mask_write ,0xF80060BC ,0x00FFFFFF ,0x00000000
    ,mask_write ,0xF80060C4 ,0x00000003 ,0x00000000
    ,mask_write ,0xF80060C8 ,0x000000FF ,0x00000000
    ,mask_write ,0xF80060DC ,0x00000001 ,0x00000000
    ,mask_write ,0xF80060F0 ,0x0000FFFF ,0x00000000
    ,mask_write ,0xF80060F4 ,0x0000000F ,0x00000008
    ,mask_write ,0xF8006114 ,0x000000FF ,0x00000000
    ,mask_write ,0xF8006118 ,0x7FFFFFFF ,0x40000001
    ,mask_write ,0xF800611C ,0x7FFFFFFF ,0x40000001
    ,mask_write ,0xF8006120 ,0x7FFFFFFF ,0x40000001
    ,mask_write ,0xF8006124 ,0x7FFFFFFF ,0x40000001
    ,mask_write ,0xF800612C ,0x000FFFFF ,0x00033C03
    ,mask_write ,0xF8006130 ,0x000FFFFF ,0x00034003
    ,mask_write ,0xF8006134 ,0x000FFFFF ,0x0002F400
    ,mask_write ,0xF8006138 ,0x000FFFFF ,0x00030400
    ,mask_write ,0xF8006140 ,0x000FFFFF ,0x00000035
    ,mask_write ,0xF8006144 ,0x000FFFFF ,0x00000035
    ,mask_write ,0xF8006148 ,0x000FFFFF ,0x00000035
    ,mask_write ,0xF800614C ,0x000FFFFF ,0x00000035
    ,mask_write ,0xF8006154 ,0x000FFFFF ,0x00000083
    ,mask_write ,0xF8006158 ,0x000FFFFF ,0x00000083
    ,mask_write ,0xF800615C ,0x000FFFFF ,0x0000007F
    ,mask_write ,0xF8006160 ,0x000FFFFF ,0x00000078
    ,mask_write ,0xF8006168 ,0x001FFFFF ,0x00000124
    ,mask_write ,0xF800616C ,0x001FFFFF ,0x00000125
    ,mask_write ,0xF8006170 ,0x001FFFFF ,0x00000112
    ,mask_write ,0xF8006174 ,0x001FFFFF ,0x00000116
    ,mask_write ,0xF800617C ,0x000FFFFF ,0x000000C3
    ,mask_write ,0xF8006180 ,0x000FFFFF ,0x000000C3
    ,mask_write ,0xF8006184 ,0x000FFFFF ,0x000000BF
    ,mask_write ,0xF8006188 ,0x000FFFFF ,0x000000B8
    ,mask_write ,0xF8006190 ,0xFFFFFFFF ,0x10040080
    ,mask_write ,0xF8006194 ,0x000FFFFF ,0x0001FC82
    ,mask_write ,0xF8006204 ,0xFFFFFFFF ,0x00000000
    ,mask_write ,0xF8006208 ,0x000F03FF ,0x000803FF
    ,mask_write ,0xF800620C ,0x000F03FF ,0x000803FF
    ,mask_write ,0xF8006210 ,0x000F03FF ,0x000803FF
    ,mask_write ,0xF8006214 ,0x000F03FF ,0x000803FF
    ,mask_write ,0xF8006218 ,0x000F03FF ,0x000003FF
    ,mask_write ,0xF800621C ,0x000F03FF ,0x000003FF
    ,mask_write ,0xF8006220 ,0x000F03FF ,0x000003FF
    ,mask_write ,0xF8006224 ,0x000F03FF ,0x000003FF
    ,mask_write ,0xF80062A8 ,0x00000FF7 ,0x00000000
    ,mask_write ,0xF80062AC ,0xFFFFFFFF ,0x00000000
    ,mask_write ,0xF80062B0 ,0x003FFFFF ,0x00005125
    ,mask_write ,0xF80062B4 ,0x0003FFFF ,0x000012A8
    ,mask_write ,0xF8006000 ,0x0001FFFF ,0x00000081
    ,mask_poll ,0xF8006054 ,0x00000007
]; 

ps7_mio_init_data =[
    mask_write ,0xF8000008 ,0x0000FFFF ,0x0000DF0D
    ,mask_write ,0xF8000B40 ,0x00000FFF ,0x00000600
    ,mask_write ,0xF8000B44 ,0x00000FFF ,0x00000600
    ,mask_write ,0xF8000B48 ,0x00000FFF ,0x00000672
    ,mask_write ,0xF8000B4C ,0x00000FFF ,0x00000672
    ,mask_write ,0xF8000B50 ,0x00000FFF ,0x00000674
    ,mask_write ,0xF8000B54 ,0x00000FFF ,0x00000674
    ,mask_write ,0xF8000B58 ,0x00000FFF ,0x00000600
    ,mask_write ,0xF8000B5C ,0xFFFFFFFF ,0x00D6861C
    ,mask_write ,0xF8000B60 ,0xFFFFFFFF ,0x00F9861C
    ,mask_write ,0xF8000B64 ,0xFFFFFFFF ,0x00F9861C
    ,mask_write ,0xF8000B68 ,0xFFFFFFFF ,0x00D6861C
    ,mask_write ,0xF8000B6C ,0x00007FFF ,0x00000E09
    ,mask_write ,0xF8000B70 ,0x00000021 ,0x00000021
    ,mask_write ,0xF8000B70 ,0x00000021 ,0x00000020
    ,mask_write ,0xF8000B70 ,0x07FFFFFF ,0x00000823
    ,mask_write ,0xF8000700 ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000704 ,0x00003FFF ,0x00000702
    ,mask_write ,0xF8000708 ,0x00003FFF ,0x00000702
    ,mask_write ,0xF800070C ,0x00003FFF ,0x00000702
    ,mask_write ,0xF8000710 ,0x00003FFF ,0x00000702
    ,mask_write ,0xF8000714 ,0x00003FFF ,0x00000702
    ,mask_write ,0xF8000718 ,0x00003FFF ,0x00000702
    ,mask_write ,0xF800071C ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000720 ,0x00003FFF ,0x00000702
    ,mask_write ,0xF8000724 ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000728 ,0x00003FFF ,0x00000600
    ,mask_write ,0xF800072C ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000730 ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000734 ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000738 ,0x00003FFF ,0x00000600
    ,mask_write ,0xF800073C ,0x00003FFF ,0x00000600
    ,mask_write ,0xF8000740 ,0x00003FFF ,0x00000302
    ,mask_write ,0xF8000744 ,0x00003FFF ,0x00000302
    ,mask_write ,0xF8000748 ,0x00003FFF ,0x00000302
    ,mask_write ,0xF800074C ,0x00003FFF ,0x00000302
    ,mask_write ,0xF8000750 ,0x00003FFF ,0x00000302
    ,mask_write ,0xF8000754 ,0x00003FFF ,0x00000302
    ,mask_write ,0xF8000758 ,0x00003FFF ,0x00000303
    ,mask_write ,0xF800075C ,0x00003FFF ,0x00000303
    ,mask_write ,0xF8000760 ,0x00003FFF ,0x00000303
    ,mask_write ,0xF8000764 ,0x00003FFF ,0x00000303
    ,mask_write ,0xF8000768 ,0x00003FFF ,0x00000303
    ,mask_write ,0xF800076C ,0x00003FFF ,0x00000303
    ,mask_write ,0xF8000770 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF8000774 ,0x00003FFF ,0x00000305
    ,mask_write ,0xF8000778 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF800077C ,0x00003FFF ,0x00000305
    ,mask_write ,0xF8000780 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF8000784 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF8000788 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF800078C ,0x00003FFF ,0x00000304
    ,mask_write ,0xF8000790 ,0x00003FFF ,0x00000305
    ,mask_write ,0xF8000794 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF8000798 ,0x00003FFF ,0x00000304
    ,mask_write ,0xF800079C ,0x00003FFF ,0x00000304
    ,mask_write ,0xF80007A0 ,0x00003FFF ,0x00000380
    ,mask_write ,0xF80007A4 ,0x00003FFF ,0x00000380
    ,mask_write ,0xF80007A8 ,0x00003FFF ,0x00000380
    ,mask_write ,0xF80007AC ,0x00003FFF ,0x00000380
    ,mask_write ,0xF80007B0 ,0x00003FFF ,0x00000380
    ,mask_write ,0xF80007B4 ,0x00003FFF ,0x00000380
    ,mask_write ,0xF80007B8 ,0x00003F01 ,0x00000201
    ,mask_write ,0xF80007BC ,0x00003F01 ,0x00000201
    ,mask_write ,0xF80007C0 ,0x00003FFF ,0x000002E0
    ,mask_write ,0xF80007C4 ,0x00003FFF ,0x000002E1
    ,mask_write ,0xF80007C8 ,0x00003FFF ,0x00000201
    ,mask_write ,0xF80007CC ,0x00003FFF ,0x00000201
    ,mask_write ,0xF80007D0 ,0x00003FFF ,0x00000280
    ,mask_write ,0xF80007D4 ,0x00003FFF ,0x00000280
    ,mask_write ,0xF8000830 ,0x003F003F ,0x002F002E
    ,mask_write ,0xF8000004 ,0x0000FFFF ,0x0000767B
];

ps7_peripherals_init_data=[
    mask_write ,0xE0001034 ,0x000000FF ,0x00000006
    ,mask_write ,0xE0001018 ,0x0000FFFF ,0x0000003E
    ,mask_write ,0xE0001000 ,0x000001FF ,0x00000017
    ,mask_write ,0xE0001004 ,0x00000FFF ,0x00000020
    ,mask_write ,0xE000D000 ,0x00080000 ,0x00080000
    ,mask_write ,0xF8007000 ,0x20000000 ,0x00000000
];




	(* initialization procedure -- parses data from above and executes. This approach was chosen because it would not produce as many instructions
		as would be required if everything was done with procedure calls. This is even more true on ARM platform, where the large immediates would be stored
		in (instruction) memory anyway.
	*)
	PROCEDURE InitSubset(CONST data: ARRAY [*] OF LONGINT);
	VAR val, valo, mask: SET; i: LONGINT; opcode, adr: LONGINT;
	BEGIN
		i := 0;
		WHILE i < LEN(data,0) DO
			opcode := data[i];
			IF opcode = mask_write THEN
				adr := data[i+1]; mask := SYSTEM.VAL(SET,data[i+2]); val := SYSTEM.VAL(SET,data[i+3]); INC(i,4);
				SYSTEM.GET(adr, valo);
				val := mask*val + (-mask) * valo;
				SYSTEM.PUT(adr, val);
			ELSIF opcode = mask_poll THEN
				adr := data[i+1]; mask := SYSTEM.VAL(SET, data[i+2]); INC(i,3);
				REPEAT
					SYSTEM.GET(adr, val)
				UNTIL val * mask # {}
			END;
		END;
	END InitSubset;

	PROCEDURE InitializeHW;
	BEGIN
		InitSubset(ps7_mio_init_data);
		InitSubset(ps7_pll_init_data);
		InitSubset(ps7_clock_init_data);
		InitSubset(ps7_ddr_init_data);
		InitSubset(ps7_peripherals_init_data);
	END InitializeHW;
END ZynqInitializer.