	.text
	.section .mdebug.abiO32
	.previous
	.file	"ch10_1.c"
                                        # Start of file scope inline assembly
ld $2, 8($sp)
st $0, 4($sp)
addiu $3, $ZERO, 0
add $v1, $at, $v0
sub $3, $2, $3
mul $2, $1, $3
div $3, $2
divu $2, $3
and $2, $1, $3
or $3, $1, $2
xor $1, $2, $3
mult $4, $3
multu $3, $2
mfhi $3
mflo $2
mthi $2
mtlo $2
sra $2, $2, 2
rol $2, $1, 3
ror $3, $3, 4
shl $2, $2, 2
shr $2, $3, 5
cmp $sw, $2, $3
jeq $sw, 20
jne $sw, 16
jlt $sw, -20
jle $sw, -16
jgt $sw, -4
jge $sw, -12
jsub 0x000010000
jr $4
ret $lr
jalr $t9
li $3, 0x00700000
la $3, 0x00800000($6)
la $3, 0x00900000

                                        # End of file scope inline assembly

	.ident	"clang version 8.0.0 "
	.section	".note.GNU-stack","",@progbits
