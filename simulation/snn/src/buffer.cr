require "./event"

class Buffer(P)
  private class Cell(P)
    getter sequence : Atomic(UInt64)
    property event : Event(P)

    def initialize(seq : UInt64)
      @sequence = Atomic(UInt64).new(seq)
      dummy_payload = uninitialized P
      @event = Event.new(0_u32, 0_u64, 0_u64, dummy_payload)
    end
  end

  getter capacity : UInt32
  @mask : UInt64
  @buffer : Array(Cell(P))
  @tail : Atomic(UInt64)
  @head : UInt64

  def initialize(@capacity : UInt32 = BUFFER_CAPACITY)
    unless @capacity >= 2 && (@capacity & (@capacity - 1)) == 0
      raise ArgumentError.new("Capacity must be a power of two and at least 2")
    end

    @mask = (@capacity - 1).to_u64
    @buffer = Array(Cell(P)).new(@capacity) { |i| Cell(P).new(i.to_u64) }
    @tail = Atomic(UInt64).new(0_u64)
    @head = 0_u64
  end

  def clear : Nil
    @buffer.each_with_index do |cell, index|
      cell.sequence.set(index.to_u64)
    end

    @head = 0_u64
    @tail.set(0_u64)
    nil
  end

  def drained? : Bool
    @tail.get == @head
  end

  def push(event : Event(P)) : Bool
    pos = @tail.get
    loop do
      cell = @buffer[(pos & @mask).to_i]
      seq = cell.sequence.get
      dif = seq.to_i64 - pos.to_i64

      if dif == 0
        res = @tail.compare_and_set(pos, pos + 1)
        if res[1]
          cell.event = event
          cell.sequence.set(pos + 1)
          return true
        else
          pos = res[0]
        end
      elsif dif < 0
        return false
      else
        pos = @tail.get
      end
    end
  end

  def pop : Event(P)?
    pos = @head
    cell = @buffer[(pos & @mask).to_i]
    seq = cell.sequence.get
    dif = seq.to_i64 - (pos + 1).to_i64

    if dif == 0
      event = cell.event
      cell.sequence.set(pos + @mask + 1)
      @head = pos + 1
      event
    else
      nil
    end
  end

  def empty? : Bool
    pos = @head
    cell = @buffer[(pos & @mask).to_i]
    seq = cell.sequence.get
    dif = seq.to_i64 - (pos + 1).to_i64
    dif != 0
  end

  def size : UInt32
    t = @tail.get
    h = @head
    t >= h ? (t - h).to_u32 : 0_u32
  end


  def debug_pending(label : String) : Nil
    head = @head
    tail = @tail.get
    return if head == tail

    cell = @buffer[(head & @mask).to_i]
    sequence = cell.sequence.get

    STDERR.puts "#{label}: head=#{head}, tail=#{tail}, sequence=#{sequence}"

    if sequence == head + 1_u64
      event = cell.event
      STDERR.puts "  first_event_time=#{event.scheduled_time}"
    else
      STDERR.puts "  head cell is NOT published; expected sequence=#{head + 1_u64}"
    end
    nil
  end
end
