root = this || window
j = $

root.toHex = (d) ->
  #console.log d
  hex = Number(d).toString(16)
  padding = (if typeof (padding) is "undefined" or padding is null then padding = 2 else padding)
  hex = "0" + hex  while hex.length < padding
  return "#"+hex

root.megaPromise = (promArr) ->
  megaDefer = w.defer()  
  countDown = promArr.length
  for prom in promArr
    prom.then ->
      countDown--
      megaDefer.resolve() if countDown <= 0
  return megaDefer.promise        

root.dummyPromise = (ctx, func) ->
  ->
    d = w.defer()
    func.call(ctx)
    d.resolve
    d.promise

class Bit
  constructor: (@addr, @value = false) ->
    @hexAddr = toHex(@addr) 
    @bit = j("<div class='bit #{@value}' index=#{@addr}>#{@hexAddr}</div>")
    
  elem: () -> j("[index=#{@addr}]")

  swap: () ->
    @set(!@value)
   
  set: (value) ->
    @elem().removeClass(@value+'')
    @value = value
    @elem().addClass(@value+'')


class Tape
  constructor: (@bits) ->

  snapshot: () -> 
    data = {}
    for v in @bits.slice(0,16)
      data[v.addr] = v.value
    return data
  restore: (data) ->
    for k,v of data
      @bits[k].set v







class Cursor
  constructor: (@at, @host) ->
    @at = @host.getFirstAddr() unless @at?
    @draw()

  draw: () ->
    j(".head").each ->
      j(@).removeClass "head"
    @myBit().addClass "head"

  myBit: () -> j("[index=#{@at}]")

  move: (d) => @_move(d)
  _move: (d) ->    
    console.log "move", @at
    @at = @host.getIndex(@at, d)    
    @draw()

class Head extends Cursor
  constructor: (@at, @host) ->
    super(@at, @host)  

  move: (d, record) =>
    if record 
      op = new Move(d)
      root.program().addOp(op)
      op.exec() 
    else 
      @_move(d)

  seek: (at) ->
    @at = at
    #op = new Seek(at)
    #root.program().addOp(op)
    @draw()

  test: () ->
    (@myBit().attr "is") is "1"

  read: () => @_read()
  _read: () -> root.tape.bits[@at].value

  write: (value) ->
    root.tape.bits[@at].set value
    @draw()

  commit: () ->
    # transform any current Move op into Seek
    editOp = root.program().latestOp()
    if root.activeCursor is root.head and editOp?.type is "Move"
      #re-render into Seek op
      root.program().removeOp editOp
      root.program().addOp new Seek(root.head.at)

    
class Op
  constructor: (@type, @param) ->        
    @param = ko.observable(@param)
    @display = ""
    @displayAddr = ko.observable(@addr || 0)
  exec: (cs = null) -> 
    @_exec()
    @next(cs) if cs?
  _exec: () -> 
  displayAddr: () -> return ''
  merge: (op, actions) -> actions.push(op)
  next: (cs) ->
    cs.peek().incrementPos()


class Swap extends Op 
  constructor: () ->
    super("Swap")
  _exec: () ->
    root.tape.bits[root.head.at].swap()
  merge: (op, actions) -> actions.pop()


class Move extends Op 
  constructor: (delta) ->
    super("Move", delta)
    @display = ko.computed () => @param()
  _exec: () -> 
    #d = w.defer()
    console.log "move", this
    root.head.move(@param())
  merge: (op) -> @param(@param() + op.param())


class EOP extends Op
  constructor: () ->
    super("EOP")
  next: (cs) ->
    if cs.frames().length > 1
      cs.pop()
    else
      cs.peek().reset()


class Seek extends Op
  constructor: (target) ->
    super("Seek", target)
    @display = ko.computed () => toHex @param()
  _exec: ->
    root.head.seek @param()
  merge: (op, actions) ->  
    @param(op.param())
    

class Jump extends Op
  constructor: (target) ->
    super("Jump", target)    
    @display = ko.computed () => toHex @param()
  _exec: () ->  
  next: (cs) ->
    cs.switchProgram(root.fu.getProg(@param()))

  ###  d = w.defer()
    current = root.program()
    root.program root.fu.getProg(@param())
    root.program().exec().then ->
      root.program(current)
      d.resolve()
    d.promise###


class If extends Op
  constructor: (@condition = true) ->
    super("If", @condition)
    @display = ko.computed () => @param().toString()  
  next: (cs) ->
    cs.peek().incrementPos()
    cs.peek().incrementPos() unless root.head.read() is @param()
  merge: () ->
    @param(!@param()) #toggle

class Ifs extends Op
  constructor: (@condition = true) ->
    super("Ifs", @condition)
    @display = ko.computed () => @param().toString()  
  next: (cs) ->
    cs.peek().incrementPos()
    cs.peek().incrementPos() unless root.bitStack.pop() is @param()
  merge: () ->
    @param(!@param()) #toggle

class Push extends Op
  constructor: () ->
    super("Push")
  _exec: () ->
    b = root.head.read()
    bit = {
      addr: ko.observable(root.head.at)
      value: ko.observable(b)
    }
    root.bitStack.push(bit)


class Pop extends Op
  constructor: () ->
    super("Pop")
  _exec: () ->
    bit = root.bitStack.pop()
    if bit?
      root.head.write(bit.value())


class Program
  constructor: (@addr, @name, @savedOps) ->
    @addr = ko.observable(@addr)
    @displayAddr = ko.computed ->
        toHex @addr()
      , this
    @name = ko.observable(if @name then @name else "new program")
    @ops = ko.observableArray() 

    for op in ko.utils.unwrapObservable(@savedOps || [])
      op = root.opFactory(ko.utils.unwrapObservable(op.type), ko.utils.unwrapObservable(op.param))
      @pushOp op

    @addOp(new EOP()) 
    @changed = ko.observable(false)
    @changed.subscribe (ch) => 
      if ch
        @save()
        root.save() 

  hasAddr: (addr) ->
    opHasAddr = (op) -> 
      op.addr() is addr
    return ko.utils.arrayFirst(@ops(), opHasAddr)?
  rename: () => @_rename()
  _rename: () ->
    name = window.prompt 'Enter program name', @name()
    return unless name? and name.length > 0
    @name(name)
    @changed(true)
  save: () ->
    #@rename()
    root.fu.addProg(this)
    @changed(false)

  pushOp: (op) ->
    # Operation ADDR is based off of Program ADDR + pos 
    # in ops array. Computation is in the Program scope:
    opaddr = () -> @addr() + @ops.indexOf(op)
    op.addr = ko.computed(opaddr, this)

    # Display ADDR is based on the op Addr alone - this = op:
    opdaddr = () -> toHex(@addr?())
    op.displayAddr = ko.computed(opdaddr, op)
    op.addr.subscribe (newAddr) -> 
      root.tape.bits[newAddr] = op
    @ops.push op
    
  addOp: (op) ->    
    latest = @latest() 
    if latest?.type is "EOP"
      eop = @ops.pop()
      latest = @latest()
    actions = ((context) -> 
      return {
        push: -> context.pushOp.call context, op
        pop: -> context.ops.pop op
        none: -> #...
      }
    )(this)

    @changed?(true) 

    if (latest?.type is op.type) 
      latest.merge(op, actions)
    else
      actions.push op
    @pushOp eop if eop? and op?.type isnt "EOP"

  removeOp: (op) => @_removeOp(op)
  _removeOp: (op) -> @ops.remove(op)

  arr: () -> @ops()

  start: () -> @addr()
  size: () -> @arr().length

  getAddr: (op) ->
    @addr() + "" + @ops.indexOf(op)

  getOp: (addr) -> ko.utils.arrayFirst(@ops(), (o) -> o?.addr() is addr)

  latest: () -> @arr()[@arr().length - 1]   
  latestOp: () -> 
    if @arr().length > 1 
      return @arr()[@arr().length - 2]
    else 
      return null
  latestAddr: () -> @addr() + @arr().length-1


class CursorController
  constructor: (@host) ->

  getIndex: (i, d) ->
    newPos = i - @host.start() + d
    if newPos >= 0
      return (newPos % @host.size()) + @host.start()
    else
      return @host.size() + @host.start() + newPos


class FuBar
  constructor: (@savedProgs) ->
    @progs = ko.observableArray()        
    @progs.equalityCompar = (a, b) -> a.addr() is b.addr()
    for prog in ko.utils.unwrapObservable(@savedProgs || [])      
      @addProg(new Program(prog.addr, prog.name, prog.ops))
    
  nextAddress: () ->
    maxAddr = 0
    ko.utils.arrayForEach(@progs(), (prog) -> maxAddr = prog.addr() if prog.addr() > maxAddr) 
    return maxAddr + 0x1000

  isSaved: (prog) ->
    return @progs.indexOf(prog) > -1

  newProgram: (name = null) ->
    addr = @nextAddress()
    #addr += root.program() !@isSaved(root.program())
    prog = new Program(addr, name)
    @addProg(prog)
    return prog

  getProg: (addr) ->
    return ko.utils.arrayFirst(@progs(), (prog) ->
      prog.addr() is addr or prog.hasAddr(addr))

  delProgram: (prog) => @_delProgram prog
  _delProgram: (prog) ->
    @progs.remove(prog)

  # For implementing CursorController
  getFirstAddr: () -> @progs()[0].addr()

  addProg: (prog) ->    
    exists = @progs.indexOf(prog) > -1
    if exists 
      existing = @getProg(prog.addr()) 
      prog.addr(existing.addr())
      i = @progs.indexOf existing
      @progs()[i] = prog
      return
    @progs.unshift(prog)

    # find program instance with matching index = i
  getIndex: (i, d) ->
    progAtIndex = ko.utils.arrayFirst(@progs(), (prog) -> prog.addr() is i) 
    # get index of that program
    arrIndex = @progs.indexOf(progAtIndex)
    # toss index to internal controller for "1-step" handling    
    newIndex = new CursorController(this).getIndex(arrIndex, d)
    return @progs()[newIndex].addr()
    
  start: () -> 0
  size: () -> @progs().length

  getCursor: () ->
    newProg = new Program(@nextAddress())
    newProg.name("<create new program>")
    @addProg(newProg)
    useJumpSelection = () => 
      addr = root.activeCursor.at    
      prog = @getProg(addr)
      newSelected = prog.addr() is newProg.addr()
      if newSelected
        prog.rename()        
      else 
        @delProgram(newProg)
      op = new Jump(addr)
      root.program().addOp op
      #op.exec(root.callstack)
      #root.program(root.callstack.peek().program)
      root.callstack.switchProgram(prog)
      if newSelected
        root.program(prog)
      else
        firstFrame = root.callstack.peek()
        eopAddr = firstFrame.program.latestAddr()
        while firstFrame.pos isnt eopAddr
          root.callstack.step()

      root.activeCursor.commit = null
      root.activeCursor = root.head
      root.head.draw()   
    c = new Cursor(null, root.fu)
    c.commit = useJumpSelection
    return c

class Frame
  constructor: (@addr) ->
    @program = root.fu.getProg(@addr)        
    @program.ops.subscribe (ops) =>      
      @pos = @program.latestAddr() - 1
      @showPos()           
    @saveEntryState()
    @reset()
  saveEntryState: () ->
    @runState = root.getSnapshot()
  restore: () ->
    root.setSnapshot(@runState)
    @reset()
  step: () ->
    op = root.tape.bits[@pos]
    console.log "Executing op #{toHex(@pos)} (#{op.type})"
    return op.exec(root.callstack)
  reset: () -> 
    @pos = @addr
    @showPos()
  incrementPos: (pos) -> 
    @pos++
    @showPos()
  showPos: () -> 
    _.defer =>
      level = root.callstack.indexOf this
      el = j('[level="' + level + '"]')
      console.log el
      el.find(".pos").removeClass "pos"
      el.find("[index=#{@pos}]").addClass "pos" 


class CallStack
  constructor: (addr) -> 
    @frames = ko.observableArray()
    @_push(addr)    
  peek: () -> @frames()[@frames().length - 1]
  _push: (addr) -> @frames.push(new Frame(addr))
  pop: (addr) -> 
    if @peek().program is root.program()
      edit = true
    @frames.pop()
    @peek().incrementPos()
    if edit?
      root.program @peek().program
    return @peek()
  step: () -> @peek().step()
  isEditing: (prog) -> 
    return prog is root.program()
  indexOf: (frame) -> @frames.indexOf(frame)
  switchProgram: (prog, clearStack = false) =>
    prog = root.fu.newProgram() unless prog?
    if clearStack
      root.program(prog)
      @frames([])
    @_push(prog.addr())
  ###snapshot: () ->
    frames = []
    xferFunction = (f) ->
      framedata = {}
      framedata.program = 
        addr: f.program.addr()
        name: f.program.name()
        ops: ko.toJS(f.program.ops)
      framedata.pos = f.pos # exec pos            
    return ko.util.arrayMap @frames, xferFunction
  restore: ###

class BitStack
  constructor: () ->
    @items = ko.observableArray()
  push: (bit) -> @items.unshift(bit)
  pop: () -> 
    if (@items().length > 0)
      return @items.shift()
    return null
  snapshot: () ->
    return ko.toJS(@items)
  restore: (data) ->
    @items(data)


root.getSnapshot = () ->  
  tape = root.tape.snapshot() 
  bitStack = root.bitStack.snapshot()
  headAt = root.head.at
  return {
    tape: tape
    bitStack: bitStack
    headAt: headAt
  }
root.setSnapshot = (data) ->
  root.tape.restore(data.tape) 
  root.bitStack.restore(data.bitStack)
  root.head.seek(data.headAt)

root.save = () ->
  localStorage['fu'] = ko.toJSON root.fu
  time = new Date().getTime()
  localStorage["fu#{time}"] = ko.toJSON root.fu

root.load = () ->
  fuStr = localStorage['fu'] 
  if fuStr? and fuStr.length > 0
    fus = JSON.parse fuStr
    if fus?.progs?
      root.fu = new FuBar(fus.progs)
      return 
  root.fu = new FuBar()

root.selectJumpProg = () ->  
  root.activeCursor = root.fu.getCursor()

root.keyDown = (e) ->  
  console.log e.which 
  
  if e.which is 38 # up
    root.activeCursor.move(-1, true)   

  if e.which is 40 # down
    root.activeCursor.move(1, true) 
    
  if e.shiftKey # jump 
    if root.activeCursor is root.head
      root.selectJumpProg()
    else
      root.activeCursor.commit?()

  if e.which is 96 or e.which is 48 # 0    
    console.log 'restoring'
    root.callstack.peek().restore()

  if e.ctrlKey
    if e.which is 82 
      window.location.reload()
    else 
      op = new If()
      root.program().addOp op
  
  if e.which is 9 # tab
    root.program().save()
    root.save()
    if root.callstack.frames().length > 1      
      root.callstack.frames.pop()
      root.program(root.callstack.peek().program)
    else
      root.callstack.switchProgram()
  
  if e.which is 27 # esc - clears all (for now)
    localStorage["fu"] = ''
    window.location.reload()
  
  if e.which is 78 # n        
    prog = root.fu.newProgram()    
    #root.callstack.push prog.addr()
    #root.program(prog)  
    root.callstack.switchProgram prog

  if e.which > 48 and e.which < 58 # 1-9
    prog = root.fu.progs()[e.which-49]
    root.callstack.switchProgram prog if prog?       

  if e.which is 13 # enter 
    root.activeCursor?.commit?()

  if e.which is 88 # x 
    op = new Ifs()
    op.exec()
    root.program().addOp(op)

  if e.altKey 
    op = new Swap()
    root.program().addOp op
    op.exec() 

  if e.which is 32 # space
    root.callstack.step()

  if e.which is 82 # r
    firstFrame = root.callstack.frames()[0]
    eopAddr = firstFrame.program.latestAddr()
    while root.callstack.frames()[0].pos isnt eopAddr
      root.callstack.step()


  if e.which is 8 # backspace
    op = root.program().latestOp()
    root.program().removeOp(op) if op?

  if e.which is 39 # right
    op = new Push()
    op.exec()
    root.program().addOp(op)
  if e.which is 37 # left
    op = new Pop()
    op.exec()
    root.program().addOp(op)

  # allow F5 + F12
  unless e.which is 116 or e.which is 123 
    e.preventDefault()

bootstrap = () ->
  arr = []
  for a in [0..15]
    arr[a] = new Bit(a, false)
    j(".strip.memory").append(arr[a].bit)
  root.tape = new Tape(arr)
  root.fu = new FuBar()
  root.load()  
  #root.program.subscribe (p) -> 
  #    root.pos = p.addr()
  #    console.log "IP updated"
  root.head = new Head 0, new CursorController
    start: () -> 0
    size: () -> 16  
  root.bitStack = new BitStack()
  root.activeCursor = root.head    
  prog = root.fu.newProgram('new program')#new Program(root.fu.nextAddress())    
  root.program = ko.observable(prog)
  root.callstack = new CallStack(root.program().addr())

  ko.applyBindings root, j('body').get(0)

root.ops = 
  Op: Op
  Move: Move
  Seek: Seek
  Swap: Swap
  Jump: Jump
  If: If
  Ifs: Ifs
  EOP: EOP
  Push: Push
  Pop: Pop

root.opFactory = (type, param) ->
  return new root.ops[type](param)

bootstrap()

