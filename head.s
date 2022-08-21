# head.s 包含 32 位保护模式初始化设置代码、时钟中断代码、系统调用中断代码和两个任务的代码。
# 在初始化完成之后程序移动到任务 0 开始执行，并在时钟中断控制下进行任务 0 和 1 之间的切换操作。
SCRN_SEL	= 0x18			# 屏幕显示内存段选择符。
TSS0_SEL	= 0x20			# 任务 0 的 TSS 段选择符。
LDT0_SEL	= 0x28			# 任务 0 的 LDT 段选择符。
TSS1_SEL	= 0x30			# 任务 1 的 TSS 段选择符。
LDT1_SEL	= 0x38			# 任务 1 的 LDT 段选择符。
.global startup_32
.code32
.text
startup_32:
# 首先加载数据段寄存器 DS、堆栈段寄存器 SS 和堆栈指针 ESP。所有段的线性基地址都是 0。
	movl	$0x10, %eax		# 0x10 是 GDT 中数据段选择符。
	mov	%ax, %ds
	lss	init_stack, %esp
# 在新的位置重新设置 IDT 和 GDT 表
	call	setup_idt		# 设置 IDT。先把 256 个中断门都填默认处理过程的描述符。
	call	setup_gdt		# 设置 GDT。
	movl	$0x10, %eax		# 在改变了 GDT 之后重新加载所有段寄存器。
	mov	%ax, %ds
	mov	%ax, %es
	mov	%ax, %fs
	mov	%ax, %gs
	lss	init_stack, %esp
# 设置 8253 定时芯片。把计数器通道 0 设置成每隔 10 毫秒向中断控制器发送一个中断请求信号。
	movb	$0x36, %al		# 控制字： 设置通道 0 工作在方式 3、计数初值采用二进制。
	movl	$0x43, %edx		# 8253 芯片控制字寄存器写端口。
	outb	%al, %dx
	movl	$11930, %eax		# 初始值设置为 (1193180/100)，即频率 100HZ。
	movl	$0x40, %edx		# 通道 0 的端口
	outb	%al, %dx		# 分两次把初始计数值写入通道 0。
	movb	%ah, %al
	outb	%al, %dx
# 在 IDT 表第 8 和第 128 (0x80) 项处分别设置定时中断门描述符和系统调用陷阱门描述符。
	movl	$0x00080000, %eax	# 中断程序属内核，即 EAX 高字是内核代码段选择符 0x0008。
	movw	$timer_interrupt, %ax	# 设置定时中断门描述符。取定时中断处理程序地址。
	movw	$0x8E00, %dx		# 中断门类型是 14 (屏蔽中断)，特权级 0 或硬件使用。
	movl	$0x08, %ecx		# 开机时 BIOS 设置的时钟中断向量号 8。这里直接使用它。
	lea	idt(,%ecx,8), %esi	# 把 IDT 描述符 0x08 地址放入 ESI 中，然后设置该描述符。
	movl	%eax, (%esi)
	movl	%edx, 4(%esi)
	movw	$system_interrupt, %ax	# 设置系统调用门描述符。取系统调用处理程序地址。
	movw	$0xef00, %dx		# 陷阱门类型是 15，特权级 3 的程序可执行。
	movl	$0x80, %ecx		# 系统调用向量号是 0x80。
	lea	idt(,%ecx,8), %esi	# 把 IDT 描述符项 0x80 地址放入 ESI 中，然后设置该描述符。
	movl	%eax, (%esi)
	movl	%edx, 4(%esi)
# 好了，现在我们为移动到任务 0 (任务A) 中执行来操作堆栈内容，在堆栈中人工建立中断返回时的场景。
	pushfl				# 复位标志寄存器 EFLAGS 中的嵌套任务标志。
	andl	$0xffffbfff, (%esp)
	popfl
	movl	$TSS0_SEL, %eax		# 把任务 0 的 TSS 段选择符加载到任务寄存器 TR。
	ltr	%ax
	movl	$LDT0_SEL, %eax		# 把任务 0 的 LDT 段选择符加载到局部描述符表寄存器 LDTR。
	lldt	%ax			# TR 和 LDTR 只需人工加载一次，以后 CPU 会自动处理。
	movl	$0, current		# 把当前任务号保存在 current 变量中。
	sti				# 现在开启中断，并在栈中营造中断返回时的场景。
	pushl	$0x17			# 把任务 0 的当前局部空间数据段 (堆栈段) 选择符入栈。
	pushl	$init_stack		# 把堆栈指针入栈 (也可以直接把 ESP 入栈) 。
	pushfl				# 把标志寄存器值入栈。
	pushl	$0x0f			# 把当前局部空间代码段选择符入栈。
	pushl	$task0			# 把代码指针入栈。
	iret				# 执行中断返回指令，从而切换到特权级 3 的任务 0 中执行。

# 以下是设置 GDT 和 IDT 中描述符项的子程序。
setup_gdt:					# 使用 6 字节操作数 lgdt_opcode 设置 GDT 表位置和长度。
	lgdt	lgdt_opcode
	ret
# 这段代码暂时设置 IDT 表中所有 256 个中断门描述符都为同一个默认值，均使用默认的中断处理过程 ignore_int。
# 设置的具体方法是：首先 eax 和 edx 寄存器对中分别设置好默认中断门描述符的 0-3 字节和 4-7 字节的内容，
# 然后利用该寄存器对循环往 IDT 表中填充默认中断门描述符内容。
setup_idt:					# 把所有 256 个中断门描述符设置为使用默认处理过程。
	lea	ignore_int, %edx		# 设置方法与设置定时中断门描述符的方法一样。
	movl	$0x00080000, %eax		# 选择符为 0x0008。
	movw	%dx, %ax
	movw	$0x8E00, %dx			# 中断门类型，特权级为 0。
	lea	idt, %edi
	mov	$256, %ecx			# 循环设置所有 256 个门描述符项。
rp_idt:
	movl	%eax, (%edi)
	movl	%edx, 4(%edi)
	addl	$8, %edi
	dec	%ecx
	jne	rp_idt
	lidt	lidt_opcode			# 最后用 6 字节操作数加载 IDTR 寄存器。
	ret

# 显示字符子程序。取当前光标位置并把 AL 中的字符显示在屏幕上。整屏可显示 80 X 25 个字符。
write_char:
	push	%gs			# 首先保存要用到的寄存器，EAX 由调用者负责保存。
	pushl	%ebx
	mov	$SCRN_SEL, %ebx		# 然后让 GS 指向显示内存段 (0xb8000)。
	mov	%bx, %gs
	movl	scr_loc, %ebx		# 再从变量 scr_loc 中取目前字符显示位置。
	shl	$1, %ebx		# 因为在屏幕上每个字符还有一个属性字节，因此字符实际显示位置对应的显示内存偏移地址要乘 2。
	movb	%al, %gs:(%ebx)
	shr	$1, %ebx		# 把字符放到显示内存后把位置除 2 加 1，此时位置对应下一个显示位置。
	incl	%ebx
	cmpl	$2000, %ebx		# 如果该位置大于 2000， 则复位成 0。
	jb	1f
	movl	$0, %ebx
1:	movl	%ebx, scr_loc		# 最后把这个位置值保存起来 (scr_loc),
	popl	%ebx			# 并弹出保存的寄存器内容，返回。
	pop	%gs
	ret

# 以下是 3 个中断处理程序：默认中断、定时中断和系统调用中断。
# ignore_int 是默认的中断处理程序，若系统产生了其他中断，则会在屏幕上显示一个字符 'C'。
.align 2
ignore_int:
	push	%ds
	pushl	%eax
	movl	$0x10, %eax		# 首先让 DS 指向内核数据段，因为中断程序属于内核。
	mov	%ax, %ds
	movl	$67, %eax		# 在 AL 中存放字符 'C' 的代码，低啊用显示程序显示在屏幕上。
	call	write_char
	popl	%eax
	pop	%ds
	iret

# 这是定时中断处理程序。其中主要执行任务切换操作。
.align 2
timer_interrupt:
	push	%ds
	pushl	%eax
	movl	$0x10, %eax		# 首先让 DS 指向内核数据段。
	mov	%ax, %ds
	movb	$0x20, %al		# 然后立刻允许其他硬件中断，即向 8259A 发送 EOI 命令。
	outb	%al, $0x20
	movl	$1, %eax
	cmpl	%eax, current
	je	1f
	movl	%eax, current		# 若当前任务是0， 则把 1 存入 current，并跳转到任务 1
	ljmp	$TSS1_SEL, $0		# 去执行。注意跳转的偏移值无用，但需要写上。
	jmp	2f
1:	movl	$0, current 		# 若当前任务是1， 则把 0 存入 current，并跳转到任务 0
	ljmp	$TSS0_SEL, $0		# 去执行。
2:	popl	%eax
	pop	%ds
	iret

# 系统调用中断 int 0x80 处理程序。 该示例只有一个显示字符功能。
.align 2
system_interrupt:
	push	%ds
	pushl	%edx
	pushl	%ecx
	pushl	%ebx
	pushl	%eax
	movl	$0x10, %edx
	mov	%dx, %ds
	call	write_char
	popl	%eax
	popl	%ebx
	popl	%ecx
	popl	%edx
	pop	%ds
	iret

/******************************************************/
current: .long 0					# 当前任务号 (0 或 1)。
scr_loc: .long 0					# 屏幕当前位置。按从左上角到右下角顺序显示。

.align 2
lidt_opcode:
	.word	256*8-1				# 加载 IDTR 寄存器的 6 字节操作数：表长度和基地址。
	.long	idt
lgdt_opcode:
	.word	(end_gdt-gdt)-1			# 加载 GDTR 寄存器的 6 字节操作数：表长度和基地址。
	.long	gdt

.align 8
idt:	.fill	256,8,0				# IDT 空间。共 256 个门描述符，每个 8 字节，占用 2KB。

gdt:	.quad	0x0000000000000000		# GDT 表。第 1 个描述符不用。
	.quad	0x00c09a00000007ff		# 第 2 个是内核代码段描述符。其选择符是 0x08。
	.quad	0x00c09200000007ff		# 第 3 个是内核数据段描述符。其选择符是 0x10。
	.quad	0x00c0920b80000002		# 第 4 个是显示内存段描述符。其选择符是 0x18。
	.word	0x0068,tss0,0xe900,0x0		# 第 5 个是 TSS0 段的描述符。其选择符是 0x20。
	.word	0x0040,ldt0,0xe200,0x0		# 第 6 个是 LDT0 段的描述符。其选择符是 0x28。
	.word	0x0068,tss1,0xe900,0x0		# 第 7 个是 TSS1 段的描述符。其选择符是 0x30。
	.word	0x0040,ldt1,0xe200,0x0		# 第 8 个是 LDT1 段的描述符。其选择符是 0x38。
end_gdt:
	.fill	128,4,0				# 初始内核堆栈空间。
init_stack:					# 刚进入保护模式时用于加载 SS:ESP 堆栈指针值。
	.long	init_stack			# 堆栈段偏移位置。
	.word	0x10				# 堆栈段同内核数据段。

# 下面是任务 0 的 LDT 表段中的局部描述符。
.align 8
ldt0:	.quad	0x0000000000000000		# 第 1 个描述符，不用。
	.quad	0x00c0fa00000003ff		# 第 2 个局部代码段描述符，对应选择符是 0x0f。
	.quad	0x00c0f200000003ff		# 第 3 个局部数据段描述符，对应选择符是 0x17。
# 下面是任务 0 的 TSS 段的内容。注意其中标号等字段在任务切换时不会改变。
tss0:	.long	0				/* back link */
	.long	krn_stk0, 0x10			/* esp0, ss0 */
	.long	0, 0, 0, 0, 0			/* esp1, ss1, esp2, ss2, cr3 */
	.long	0, 0, 0, 0, 0			/* eip, eflags, eax, ecx, edx */
	.long	0, 0, 0, 0, 0			/* ebx, esp, ebp, esi, edi */
	.long	0, 0, 0, 0, 0, 0		/* es, cs, ss, ds, fs, gs */
	.long	LDT0_SEL, 0x8000000		/* ldt, trace bitmap */

	.fill	128,4,0				# 这是任务 0 的内核空间。
krn_stk0:

# 下面是任务 1 的 LDT 表段内容和 TSS 段内容。
.align 8
ldt1:	.quad	0x0000000000000000		# 第 1 个描述符，不用。
	.quad	0x00c0fa00000003ff		# 选择符是 0x0f，基地址 = 0x0000。
	.quad	0x00c0f200000003ff		# 选择符是 0x17，基地址 = 0x0000。

tss1:	.long	0				/* back link */
	.long	krn_stk1, 0x10			/* esp0, ss0 */
	.long	0, 0, 0, 0, 0			/* esp1, ss1, esp2, ss2, cr3 */
	.long	task1, 0x200			/* eip, eflags */
	.long	0, 0, 0, 0			/* eax, ecx, edx, ebx */
	.long	usr_stk1, 0, 0, 0		/* esp, ebp, esi, edi */
	.long	0x17, 0x0f, 0x17, 0x17, 0x17, 0x17	/* es, cs, ss, ds, fs, gs */
	.long	LDT1_SEL, 0x8000000		/* ldt, trace bitmap */

	.fill	128,4,0				# 这是任务 0 的内核空间。
krn_stk1:

# 下面是任务 0 和任务 1 的程序，它们分别循环显示字符 'A' 和 'B'。
task0:
	movl	$0x17, %eax			# 首先让 DS 指向任务的局部数据段。
	movw	%ax, %ds			# 因为任务没有使用局部数据，所以这两句可省略。
	movb	$65, %al			# 把需要显示的字符 'A' 放入 AL 寄存器中。
	int	$0x80				# 执行系统调用，显示字符。
	movl	$0xfff, %ecx			# 执行循环，起延时作用。
1:	loop	1b
	jmp	task0				# 跳转到任务代码开始处继续显示字符。
task1:
	movl	$0x17, %eax			# 首先让 DS 指向任务的局部数据段。
	movw	%ax, %ds			# 因为任务没有使用局部数据，所以这两句可省略。
	movb	$66, %al			# 把需要显示的字符 'B' 放入 AL 寄存器中。
	int	$0x80				# 执行系统调用，显示字符。
	movl	$0xfff, %ecx			# 延时一段时间，并跳转到开始处继续循环显示。
1:	loop	1b
	jmp	task1				# 跳转到任务代码开始处继续显示字符。

	.fill	128,4,0				# 这是任务 1 的用户栈空间。
usr_stk1:
