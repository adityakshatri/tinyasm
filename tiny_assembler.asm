include 'tinyasm_insn_helpers.asm'
include 'tinyasm_insn_list.asm'
include 'tinyasm_registers.asm'

tiny_insns define_icodes, 0

macro noop { dw noop }
macro halt { dw halt }


macro _check_reg r {
    if ~((r eq t0)|(r eq t1)|(r eq t2)|(r eq t3))
        err "Invalid register"
    end if
}

macro _check_opsize opsize {
    if ~(opsize eq b) & ~(opsize eq w)
        err "Invalid opsize: " 
    end if
}

macro _mem_insn name* {
    macro t#name opsize*, addr*, r* \{
        _check_opsize opsize
        _check_reg r
        local matched 
        define matched 0
        match = 0 [target], matched add \\{
            if target eq t0
                dw (#name\opsize\#1\#r)
            else if ((target eq t1) | (target eq t2) | (target eq t3))
                err "addr for indirect memop must be t0"
            dw (#name\#opsize\#d\#r)
                     dw target
                  end if
                  define matched 1
            \\}
            match =0 any, matched addr
            \\{
                err "invalid address. must be [t0] or imm. value."
            \\}
      \}
}

_mem_insn stor
_mem_insn load

macro tmove opsize*, r1*, r2* {
    _check_opsize opsize
    _check_reg r1
    _check_reg r2

    if((r2 eq t0)| (r2 eq t1)| (r2 eq t2)| (r2 eq t3))
        dw (mov\#opsize\#r1\#r2)
    else
        dw movi#opsize\#r1
        if opsize eq b
            db r2
        else if opsize eq w
            dw r2
        else 
            err
        end if
    end if
}

macro _binop_alu_insn  name {
    macro t#name opsize*, r1*, r2* \{
        _check_opsize opsize
        _check_reg r1
        _check_reg r2
        dw name\#opsize\#r1\#r2
    \}
}

_binop_alu_insn add
_binop_alu_insn sub
_binop_alu_insn and
_binop_alu_insn or
_binop_alu_insn xor
_binop_alu_insn shr
_binop_alu_insn shl
_binop_alu_insn mul
_binop_alu_insn smul


macro _unop_alu_insn name {
      macro t#name opsize*, r* \{
            if ((name eq div)|(name eq sdiv)) & \
               (r eq t0)
               err "invalid instruction"
            end if
            _check_reg (#r)
            _check_opsize (#opsize)
            dw name\#opsize\#r
      \}
}


_unop_alu_insn div
_unop_alu_insn sdiv
_unop_alu_insn inv
_unop_alu_insn push
_unop_alu_insn pop

macro tsleep r* {
      _check_reg r
      dw sleep#r
}

macro tqj cond*, target* {
      if (target eq t0)
         dw j#cond#i
      else if ((target eq t1)|(target eq t2)|(target eq t3))
         err "indirect jump or call address must be held in t0"
      else
         dw j#cond#d
         dw target
      end if
}

macro tret { dw return }

macro tyld code {
      dw yld
      dw code
}

format binary
include 'test_program.inc'