format ELF64 executable 3 // TODO: buffer +++ and >>>
entry start

segment readable executable

start:
  mov rbp, rsp

  cmp qword [rsp], 1
  je exit_missing_input

  mov rax, [rsp + 16]
  mov [filename], rax

  cmp qword [rsp], 3
  jg exit_too_many_arguments
  jb skip_parsing

  xor rax, rax
  mov rsi, [rsp + 24]
  loop_parse:
    movzx rbx, byte [rsi]
    test rbx, rbx
    jz end_loop_parse
    cmp rbx, '0'
    jb exit_could_not_parse
    cmp rbx, '9'
    ja exit_could_not_parse

    sub rbx, '0'
    lea rax, [rax + rax * 4]
    shl rax, 1
    add rax, rbx

    inc rsi
    jmp loop_parse

  end_loop_parse:

  mov [memsize], rax

  skip_parsing:

  mov eax, 2 ; open
  mov rdi, [filename]
  mov rsi, 0 ; flags
  mov rdx, 0 ; mode
  syscall

  test rax, rax
  js exit_file_error

  mov [fd], eax

  mov eax, 8 ; lseek
  mov edi, [fd]
  mov esi, 0 ; offset
  mov edx, 2 ; SEEK_END
  syscall

  test rax, rax
  js exit_io_error

  mov [filesize], rax

  sub rsp, rax
  sub rsp, [memsize]
  mov [mem], rsp

  mov eax, 8 ; lseek
  mov edi, [fd]
  mov esi, 0 ; offset
  mov edx, 0 ; SEEK_SET
  syscall

  test rax, rax
  js exit_io_error

  mov rcx, [memsize]
  xor eax, eax
  mov rdi, [mem]
  cld
  rep stosb ; memset 0

  mov eax, 0 ; read
  mov edi, [fd]
  mov rsi, [mem]
  add rsi, [memsize]
  mov [ip], rsi
  mov rdx, [filesize]
  syscall

  ; [ file ][ memory ][ loop stack )
  ; ^rbp              ^rsp

  mov eax, 16 ; ioctl
  mov edi, 0 ; stdin
  mov esi, 0x5401 ; TCGETS
  mov edx, orig_termios
  syscall
  cmp eax, 4294967271 ; -ENOTTY
  je raw_mode_init_end
  test eax, eax
  js exit_io_error
  mov [isatty], 1
  mov ecx, 15 ; sizeof(struct termios) / 4
  mov esi, orig_termios
  mov edi, termios
  cld
  rep movsd
  and dword [termios + 12], 4294967285 ; c_lflag &= ~(ICANON | ECHO)
  mov byte [termios + 23], 1 ; c_cc[VMIN] = 1
  mov byte [termios + 22], 0 ; c_cc[VTIME] = 0
  mov eax, 16 ; ioctl
  mov edi, 0 ; stdin
  mov esi, 0x5402 ; TCSETS
  mov edx, termios
  syscall
  test eax, eax
  js exit_io_error
  raw_mode_init_end:

  mov ecx, 0 ; initial cell pointer
  mov ebx, 0 ; initial cell value

  main_loop:
    mov rax, [ip]
    movzx rax, byte [rax]

    cmp eax, '+'
    je case_inc
    cmp eax, '-'
    je case_dec
    cmp eax, ','
    je case_in
    cmp eax, '.'
    je case_out
    cmp eax, '<'
    je case_left
    cmp eax, '>'
    je case_right
    cmp eax, ';'
    je case_comment
    cmp eax, '['
    je case_loop
    cmp eax, ']'
    je case_end

    jmp switch_break

    case_inc:
      inc ebx
      jmp switch_break

    case_dec:
      dec ebx
      jmp switch_break

    case_in:
      mov eax, 0 ; read
      mov edi, 0 ; stdin
      mov rsi, [mem]
      lea rsi, [rsi + rcx]
      mov edx, 1 ; 1 char
      push rcx
      syscall
      pop rcx
      test eax, eax
      js exit_io_error
      mov rsi, [mem]
      movzx ebx, byte [rsi + rcx]

      jmp switch_break

    case_out:
      mov rsi, [mem]
      mov byte [rsi + rcx], bl
      mov eax, 1 ; write
      mov edi, 1 ; stdout
      mov rsi, [mem]
      lea rsi, [rsi + rcx]
      mov edx, 1 ; 1 char
      push rcx
      syscall
      pop rcx
      test eax, eax
      js exit_io_error
      mov rsi, [mem]
      movzx ebx, byte [rsi + rcx]

      jmp switch_break

    case_left:
      mov rsi, [mem]
      mov byte [rsi + rcx], bl
      dec rcx
      mov rax, rcx
      xor rdx, rdx
      mov rdi, [memsize]
      div rdi
      mov rcx, rdx
      mov rsi, [mem]
      movzx ebx, byte [rsi + rcx]

      jmp switch_break

    case_right:
      mov rsi, [mem]
      mov byte [rsi + rcx], bl
      inc rcx
      mov rax, rcx
      xor rdx, rdx
      mov rdi, [memsize]
      div rdi
      mov rcx, rdx
      mov rsi, [mem]
      movzx ebx, byte [rsi + rcx]

      jmp switch_break

    case_comment:
      push rcx
      mov rcx, -1
      mov al, 10 ; '\n'
      mov rdi, [ip]
      cld
      repne scasb
      dec rdi
      mov [ip], rdi
      pop rcx

      jmp switch_break

    case_loop:
      movzx ebx, bl
      test ebx, ebx
      jz skip_loop
      push [ip]
      jmp switch_break

      skip_loop:
        xor eax, eax
        mov rsi, [ip]
        loop_skip_loop:
          inc rsi
          movzx edx, byte [rsi]
          cmp edx, '['
          je case_char_loop
          cmp edx, ']'
          jne loop_skip_loop

          test rax, rax
          jz loop_skip_loop_end
          dec rax
          jmp loop_skip_loop

          case_char_loop:
            inc rax

          jmp loop_skip_loop

        loop_skip_loop_end:
        mov [ip], rsi

        jmp switch_break

    case_end:
      cmp rsp, [mem]
      je exit_unmatched_end

      movzx ebx, bl
      test ebx, ebx
      inc [ip]
      jz main_loop

      pop [ip]
      jmp main_loop

    switch_break:

    inc [ip]
    cmp [ip], rbp
    jne main_loop

    cmp rsp, [mem]
    jne exit_unmatched_loop

  mov edi, 0 ; success error code
exit_cleanup:
  mov rbx, rdi

  cmp [fd], -1
  je exit

  mov eax, 3 ; close
  mov edi, [fd]
  syscall

  exit:

  movzx eax, [isatty]
  test eax, eax
  jz raw_mode_restore_end
  mov eax, 16 ; ioctl
  mov edi, 0 ; stdin
  mov esi, 0x5402 ; TCSETS
  mov edx, orig_termios
  syscall
  test eax, eax
  setns [isatty]
  js exit_io_error
  raw_mode_restore_end:

  mov rdi, rbx

  mov eax, 60 ; exit
  syscall

exit_missing_input:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, missing_input_msg
  mov edx, missing_input_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

exit_too_many_arguments:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, too_many_arguments_msg
  mov edx, too_many_arguments_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

exit_could_not_parse:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, could_not_parse_msg
  mov edx, could_not_parse_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

exit_file_error:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, file_error_msg
  mov edx, file_error_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

exit_io_error:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, io_error_msg
  mov edx, io_error_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

exit_unmatched_end:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, unmatched_end_msg
  mov edx, unmatched_end_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

exit_unmatched_loop:
  mov eax, 1 ; write
  mov edi, 2 ; stderr
  mov rsi, unmatched_loop_msg
  mov edx, unmatched_loop_msg_len
  syscall

  mov rdi, 1 ; error code
  jmp exit_cleanup

segment readable writeable

  align 8
  filename     rq 1
  memsize      dq 256
  filesize     rq 1
  ip           rq 1
  mem          rq 1
  align 4
  fd           dd -1
  termios      rb 60
  orig_termios rb 60
  isatty       db 0

segment readable

  missing_input_msg db "error: Missing input", 10
  missing_input_msg_len = $ - missing_input_msg
  too_many_arguments_msg db "error: Too many arguments", 10
  too_many_arguments_msg_len = $ - too_many_arguments_msg
  could_not_parse_msg db "error: Could not parse unsigned integer", 10
  could_not_parse_msg_len = $ - could_not_parse_msg
  file_error_msg db "error: Could not open file", 10
  file_error_msg_len = $ - file_error_msg
  io_error_msg db 10, "error: Input / Output error", 10
  io_error_msg_len = $ - io_error_msg
  unmatched_end_msg db 10, "error: Unmatched ']'", 10
  unmatched_end_msg_len = $ - unmatched_end_msg
  unmatched_loop_msg db 10, "error: Unmatched '['", 10
  unmatched_loop_msg_len = $ - unmatched_loop_msg


