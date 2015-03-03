/*
 * lab1.S - LEDs and USART2 in assembly on the STM32F4-Discovery Board
 *
 * Target: STM32F4-Discovery w/ STM32F407VGT6 processor,
 *         ROM = 1M   @ 0x08000000
 *         RAM = 192k @ 0x20000000
 *
 * REFERENCES:
 *
 * All documentation references written as "[#]-<section>" where:
 *
 * [1] = RM0090 STM32F407 Reference Manual.pdf
 * [2] = STM32F4 Discovery Schematic.pdf
 *
 */
	.syntax unified   			/* Use unified style assembly syntax */
	.thumb            			/* Cortex-M3 only supports Thumb code */

    /*
     * On power-up the Cortex-M family processors expect a few pieces
     * of information to be pre-configured at a few pre-defined addresses.
     * Specifically, a table of "vectors" placed at the start of
     * memory (address 0x00000000) contains, in order:
     * 0x00000000 : Address of stack top in RAM
     * 0x00000004 : Address of code to run on start-up/reset
     * 0x00000008 : Address of a hardware fault handler routine
     *
     * The assembler directive ".type <func name>, %function" must
     * be provided for each routine listed in the vector table
     * to hint the linker to provide the correct target address for
     * routines written using "thumb" instructions
     *
     * In order to place the vector table where it belongs in memory
     * it is given the special section name "vectors". This is done
     * using the ".section" directive below so the linker knows which
     * chunk of code is the vector table and can place it where
     * required.  (See the STM32F407VG.ld linker script).
     */
	.type reset_handler, %function
	.type NMI_handler, %function
	.type fault_handler, %function
	.equ STACK_TOP, 0x20000100     /* 256 bytes of stack in RAM region */

	.section vectors
	.word STACK_TOP
	.word reset_handler    /* What to do on power-on */
	.word NMI_handler      /* Non-maskable interrupt handler */
	.word fault_handler    /* Hardware fault handler */

	/* Generic code section */
	.text

	/* In the event of a non-maskable interrupt, loop here forever */
NMI_handler:
	b NMI_handler

	/* In the event of a fault, loop here forever */
fault_handler:
	ldr r1, =GPIOD_BSRR_SET_RED
	mov r0, #1
	bl light_on
	b fault_handler

hellostring:
	.ascii "hello!!\n\r\0"
	.align 2


	/* This is the code we want to run out of reset/on start-up */
reset_handler:
	cpsid i					/* disable interupts - power-on default */

  	/* STEP 1: Enable GPIOD Peripheral Clock */
  	.equ RCC_AHB1ENR,          0x40023830  /* ([1]-2.3 Table 2) */
  	.equ RCC_AHB1ENR_GPIODEN,  0x08        /* ([1]-6.3.12) */

  	ldr r0, =RCC_AHB1ENR          /* r0=addr of GPIO Clock Enable Register */
  	ldr r1, =RCC_AHB1ENR_GPIODEN  /* r1=Port D Enable Bit */
  	str r1, [r0]			      /* Store #0x08 into address 0x40023830 */

  	/* STEP2: Configure GPIO connected to LED as output, push-pull */
   	.equ GPIOD_MODER,        0x40020C00  /* ([1]-2.3, [1]-7.4.1) */
  	.equ GPIOD_MODER_GP,     0x55000000  /* ([1]-7.4.1) */
  	ldr r0, =GPIOD_MODER
  	ldr r1, =GPIOD_MODER_GP
  	str r1, [r0]

 	/* Turn LED on for 1 second, then off */
	.equ GPIOD_BSRR,          0x40020C18  /* ([1]-2.3, [1]-7.4.7) */
	.equ GPIOD_BSRR_SET_12,   0x0000F000  /* ([1]-7.4.7 */
	.equ GPIOD_BSRR_RESET_12, 0xF0000000

	.equ GPIOD_BSRR_SET_GREEN, 	0x00001000	/*Green LED*/
	.equ GPIOD_BSRR_SET_ORANGE,	0x00002000	/*Orange LED*/
	.equ GPIOD_BSRR_SET_RED,	0x00004000	/*Red LED*/
	.equ GPIOD_BSRR_SET_BLUE,	0x00008000	/*Blue LED*/
	.equ GPIOD_BSRR_SET_GOB,	0x0000B000	/*Blue,Orange,Green LEDS*/
/*
	mov r0, #3
	bl gob_sequence

	bl call_fault
*/

	/* Initialise the USART2 peripheral */
	bl USART2_init
  	bl usart2_echo


endloop:
	b endloop  /* spin here forever in a tight loop */

/*
* Transmits "hello!!" to monitor
*/
usart2_hello:
	push {r0,r1,r2,lr}
	/*bl USART2_init*/
	ldr r1, =hellostring
	helloloopstart:
		ldrb r0, [r1]
		cmp r0, 0
		beq helloloopend
		bl USART2_send
		add r1, 1
		b helloloopstart
	helloloopend:
	pop {r0,r1,r2,pc}

newlinestring:
	.ascii "\n\r"
	.align 2

/*
 * Main USART2 program
 * Receives typed characters and echos back to terminal window
 */
usart2_echo:
	push {r0,r1,r2,lr}
	/*bl USART2_init*/
	echoloopstart:
		bl USART2_recv
		/*bl USART2_send*/		/*Echo received character*/
		bl usart2_toggle_led
		/* Go to new line after character */
		ldr r2, =newlinestring
		ldrb r0, [r2]
		bl USART2_send
		add r2, 1
		ldrb r0, [r2]
		bl USART2_send
		/*cmp r0, 0*/
		bl echoloopstart
	echoloopend:
	pop {r0,r1,r2,pc}

/*
 * Toggle LED on/off based on keyboard input
 */
	.equ GPIOD_IDR, 		0x40020C10		/*IDR address*/
	.equ IDR_GREEN_MASK,	0x00001000
	.equ IDR_ORANGE_MASK,	0x00002000
	.equ IDR_BLUE_MASK,		0x00008000
	.equ IDR_GOB_MASK,		0x0000B000
usart2_toggle_led:
	push {r0,r1,r2,r3,r4,r5,r6,lr}
	/* r0 holds received character*/
	ldr r3, =GPIOD_IDR
	ldr r4, [r3]			/* Get status of LEDS on/off */
	cmp r0, #103			/* If 'g'*/
	beq green_toggle
	cmp r0, #111			/* If 'o' */
	beq orange_toggle
	cmp r0, #98				/* If 'b' */
	beq blue_toggle
	cmp r0, #97				/* If 'a' */
	beq gob_toggle
	bl USART2_send				/* Else simply echo received character*/
	b toggle_end
 green_toggle:
	ldr r5, =IDR_GREEN_MASK
	and r4, r4, r5
	cmp r4, #0
	ldr r1, =GPIOD_BSRR_SET_GREEN
	ldr r3, =green_on		/* Transmit LED status to screen*/
	beq toggle_light
	lsl r1, 16
	ldr r3, =green_off
	bne toggle_light
 orange_toggle:
	ldr r5, =IDR_ORANGE_MASK
	and r4, r4, r5
	cmp r4, #0
	ldr r1, =GPIOD_BSRR_SET_ORANGE
	ldr r3, =orange_on
	beq toggle_light
	lsl r1, 16
	ldr r3, =orange_off
	bne toggle_light
 blue_toggle:
	ldr r5, =IDR_BLUE_MASK
	and r4, r4, r5
	cmp r4, #0
	ldr r1, =GPIOD_BSRR_SET_BLUE
	ldr r3, =blue_on
	beq toggle_light
	lsl r1, 16
	ldr r3, =blue_off
	bne toggle_light
 gob_toggle:
	ldr r5, =IDR_GOB_MASK		/*0xb000*/
	mov r6, r4					/* Move IDR info to r6 (eg. 0x1060 - green on)*/
	lsl r6, 16					/* shift up to turn off existing leds (eg. 0x10600000) */
	eor r6, r6, r5				/* add mask info to r6 (eg. 0x1060b000)*/
	eor r6, r6, r4				/* be sure to not turn on leds that were already on (eg. 0x1060a000) */
	mov r1, r6
	/*Figure out which strings should be put in r3*/
	ldr r3, =gob_string
	b toggle_light
 toggle_light:
	ldr r2, =GPIOD_BSRR		/**/
	str r1, [r2]
	bl status_to_string
/*
	bl transmit_string		/* Transmits string in r3*/

 toggle_end:
	pop {r0,r1,r2,r3,r4,r5,r6,pc}

/*
 * LED status strings
 */
blue_on:
	.ascii "BLUE ON\0"
	.align 2
blue_off:
	.ascii "BLUE OFF\0"
	.align 2
orange_on:
	.ascii "ORANGE ON\0"
	.align 2
orange_off:
	.ascii "ORANGE OFF\0"
	.align 2
green_on:
	.ascii "GREEN ON\0"
	.align 2
green_off:
	.ascii "GREEN OFF\0"
	.align 2
red_string:
	.ascii "RED\0"
	.align 2
gob_string:			/*More of a flag for the status_to_string fn than a legit string*/
	.ascii "GOB\0"
	.align 2
on_string:
	.ascii "ON\0"
	.align 2
space_string:
	.ascii " \0"
	.align 2

/*
 * Transmits string to terminal window
 * Receives string address pointer in r3
 * Each string must end with "\0"
 */
transmit_string:
	push {r0,r3,lr}
 transmit_start:
	ldrb r0, [r3]
	cmp r0, #0
	beq transmit_end
	bl USART2_send
	add r3, 1
	b transmit_start
 transmit_end:
 	ldr r3, =space_string	/* Put space at end of echoed string*/
 	ldrb r0, [r3]
 	bl USART2_send
	pop {r0,r3,pc}


/*
 * Change IDR status in r1 to LED status string
 * Used for GOB toggle
 */
status_to_string:
	push {r0,r1,r2,r3,lr}
	ldr r0, =gob_string
	cmp r3, r0
	beq gob_status		/*Give status of each LED for gob_toggle*/
	b transmit_link	/*Only give status for individual LED*/
 gob_status:
	/*blue status*/
	ldr r2, =GPIOD_BSRR_SET_BLUE
	and r0, r1, r2
	cmp r0, r2
	ldr r3, =blue_on
	beq t1
	bne not_t1
 t1:
 	bl transmit_string
 	b orange
 not_t1:
	ldr r3, =blue_off
 	bl transmit_string
	/*orange status*/
 orange:
	ldr r2, =GPIOD_BSRR_SET_ORANGE
	and r0, r1, r2
	cmp r0, r2
	ldr r3, =orange_on
	beq t2
	bne not_t2
 t2:
 	bl transmit_string
 	b green
 not_t2:
	ldr r3, =orange_off
	bl transmit_string
 green:
	/*green status*/
	ldr r2, =GPIOD_BSRR_SET_GREEN
	and r0, r1, r2
	cmp r0, r2
	ldr r3, =green_on
	beq t3
	bne not_t3
 t3:
 	b transmit_link
 not_t3:
	ldr r3, =green_off
	b transmit_link
 transmit_link:
 	bl transmit_string
	pop {r0,r1,r2,r3,pc}

		/*
		 * The IDR status comes in on r1
		 */
/*		transmit_LED_status:
			push {r0,r1,r3,lr}
			ldr r0, =GPIOD_BSRR_SET_GREEN
			cmp r0, r1
			ldr r3, =green_off
			bne transmit_start	/* LED off*/
/*			ldr r3, =green_on
			b transmit_start
		 transmit_start:
		 	ldrb r0, [r3]
			cmp r0, #0
			beq transmit_end
			bl USART2_send
			add r3, 1
			b transmit_start
		 transmit_end:
			pop {r0,r1,r3,pc}
*/

/*
 * Waits for n seconds
 * Pass n into r0
 */
waitn:
	push {r0,r1,r2,lr}
	mov r1, #0
 loopstart:
	cmp r1, r0
	bge loopend
	.equ BUSYWAIT_1_SECOND, 3200000		/* Wait for 1 second */
	ldr r2, =BUSYWAIT_1_SECOND
 waitloop:
	sub r2, r2, #1
	cmp r2, #0
	bne waitloop
	add r1, #1
	b loopstart
 loopend:
	pop {r0,r1,r2,pc}

/*
 * Turns LED on for a number of seconds
 * Pass LED address into r1
 * Pass # seconds to wait into r0
 */
light_on:
	push {r0,r1,r2,lr}
	ldr r2, =GPIOD_BSRR
	str r1, [r2]
	/*mov r0, #1*/
	bl waitn
	ldr r2, =GPIOD_BSRR
	lsl r1, 16
	str r1, [r2]
	/*mov r0, #1*/
	bl waitn
	pop {r0,r1,r2,pc}
/*
toggle_light:
	push {r0,r1,r2,lr}			/* r1 holds LED on/off signal */
/*	ldr r2, =GPIOD_BSRR		/**/
/*	str r1, [r2]

	pop {r0,r1,r2,pc}

*/
gob_sequence:
	push {r0,r1,r2,r3,lr}
	mov r2, #0
	lstart:
		cmp r2, r0
		bge lend
		mov r3, r0		/*Store r0 value while calling lights*/

		mov r0, #1
		ldr r1, =GPIOD_BSRR_SET_GREEN
		bl light_on
		ldr r1, =GPIOD_BSRR_SET_ORANGE
		bl light_on
		ldr r1, =GPIOD_BSRR_SET_BLUE
		bl light_on
		ldr r1, =GPIOD_BSRR_SET_GOB
		bl light_on

		mov r0, r3		/*Restore r0 value*/
		add r2, #1
		b lstart
	lend:
	pop {r0,r1,r2,pc}

call_fault:
	mov lr, #100
	push {r0,lr}
	pop {r0,pc}

	.end


