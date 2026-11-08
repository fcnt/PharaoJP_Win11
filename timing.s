.intel_syntax noprefix
.text

# Jumped to from the game's simulation timer, with EDI=now, ESI=elapsed,
# and EDX=the original speed-table interval in milliseconds.
# Return a count to the game loop. Keep the existing fast-forward path.
.globl _simulation_clock
_simulation_clock:
    cmp edx, 16
    jae interval_ready
    mov edx, 16
interval_ready:
    cmp esi, edx
    jb no_ticks
    cmp byte ptr [0xfe7664], 0
    jne fast_forward

    # Cap the per-loop work and skip large backlogs after stalls.
    cmp esi, 250
    jae stalled
    mov ecx, edx
    mov eax, esi
    xor edx, edx
    div ecx
    cmp eax, 4
    ja stalled

    # Advance the scheduled time by whole ticks and retain the remainder.
    sub edi, edx
    jmp save_clock
stalled:
    mov eax, 1
    jmp save_clock
fast_forward:
    mov eax, 10000
save_clock:
    mov dword ptr [0x102eda0], edi
    pop edi
    pop esi
    ret

    .org 0x60, 0x90
.globl _simulation_paused
_simulation_paused:
    # Existing pause and modal-screen checks land here.
    mov dword ptr [0x102eda0], edi
no_ticks:
    xor eax, eax
    pop edi
    pop esi
    ret
