! boot.s 程序
! 首先利用 BIOS 中断把内核代码 (head 代码) 加载到内存 0x10000 处，然后移动到内存 0 处。
! 最后进入保护模式，并跳转到内存 0 (head 代码) 开始处继续运行。
BOOTSEG = 0x07c0			! 引导扇区 (本程序) 被 BIOS 加载到内存 0x7c00 处。
SYSSEG  = 0x1000			! 内核 (head) 先加载到 0x10000 处，然后移动到 0x0 处。
SYSLEN  = 17				! 内核占用的最大磁盘扇区数。
entry start
start:
	jmpi	go,#BOOTSEG		! 段间跳转至 0x7c0:go 处。当本程序刚运行时所有段寄存器值均为 0。该跳转语句会把 CS 寄存器加载为 0x7c0 (原为 0)。
go:	mov	ax,cs			! 让 DS 和 SS 都指向 0x7c0 段。
	mov	ds,ax
	mov	ss,ax
	mov	sp,#0x400		! 设置临时栈指针。其值需大于程序末端并有一定空间即可。

! 加载内核代码到内存 0x10000 开始处。
load_system:				! 利用 BIOS 中断 int 0x13 功能 2 从启动盘读取 head 代码。
	mov	dx, #0x0000		! DH - 磁头号；DL - 驱动器号
	mov	cx, #0x0002		! CH - 10 位磁道号低 8 位；CL - 位 7、6 时磁道号高 2 位，位 5-0 起始扇区号 (从 1 计)。
	mov	ax, #SYSSEG		! ES:BX - 读入缓冲区位置 (0x1000:0x0000)。
	mov	es, ax
	xor	bx, bx
	mov	ax, #0x200+SYSLEN	! AH - 读扇区功能号；AL - 需读的扇区数 (17)。
	int	0x13
	jnc	ok_load
die:	jmp	die

! 把内核代码移动到内存 0 开始处。共移动 8KB 字节 (内核长度不超过 8KB)。
ok_load:
	cli				! 关中断
	mov	ax, #SYSSEG		! 移动开始位置 DS:SI = 0x1000:0; 目的位置 ES:DI = 0:0。
	mov	ds, ax
	xor	ax, ax
	mov	es, ax
	mov	cx, #0x2000		! 设置共移动 4K 次，每次移动一个字 (word)。
	sub	si, si
	sub	di, di
	rep				! 执行重复移动指令。
	movw
! 加载 IDT 和 GDT 基地址寄存器 IDTR 和 GDTR。
	mov	ax, #BOOTSEG
	mov	ds, ax			! 让 DS 重新指向 0x7c0 段。
	lidt	idt_48			! 加载 IDTR。6 字节操作数: 2 字节表长度，4 字节线性基地址。
	lgdt	gdt_48			! 加载 GDTR。6 字节操作数: 2 字节表长度，4 字节线性基地址。

! 设置控制寄存器 CR0 (即机器状态字), 进入保护模式。段选择符值 8 对应 GDT 表中第 2 个 段描述符。
	mov	ax, #0x0001		! 在 CR0 中设置保护模式标志 PE (位0)。
	lmsw	ax
	jmpi	0, 8			! 然后跳转至选择符指定的段中，偏移 0 处。注意此时段值已是段选择符。该段的线性基地址是0。

! 下面是全局描述符 GDT 的内容。 其中包含 3 个段描述符。第一个不用，另两个是代码和数据段描述符。
gdt:	.word	0,0,0,0			! 段描述符 0，不用。每个描述符占 8 字节。

	.word	0x07FF			! 段描述符 1。8Mb - 段限长值=2047 (2048*4096=8MB)
	.word	0x0000			! 段基地址=0x0000。
	.word	0x9A00			! 是代码段，可读/执行。
	.word	0x00C0			! 段属性颗粒度=4KB, 80386。

	.word	0x07FF			! 段描述符 2。8Mb - 段限长值=2047 (2048*4096=8MB)
	.word	0x0000			! 段基地址=0x0000。
	.word	0x9200			! 是数据段，可读写。
	.word	0x00C0			! 段属性颗粒度=4KB, 80386。
! 下面分别是 LIDT 和 LGDT 指令的 6 字节操作数。
idt_48:	.word	0			! IDT 表长度是 0。
	.word	0,0			! IDT 表的线性基地址也是 0。
gdt_48:	.word	0x7ff			! GDT 表长度是 2048 字节，可容纳 256 个描述符项。
	.word	0x7c00+gdt,0		! GDT 表的线性地址在 0x7c0 段的偏移 gdt 处。
.org 510
	.word	0xAA55			! 引导扇区有效标志。必须处于引导扇区最后 2 字节处。
