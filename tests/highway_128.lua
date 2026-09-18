local machine=manager.machine
local mem=machine.devices[':maincpu'].spaces.program
local frames=0
emu.register_frame_done(function()
    frames=frames+1
    local message=''
    for i=0,30 do message=message..string.char(mem:read_u8(0x400+i)&127) end
    if message:find('REQUIRES 256K',1,true) or frames>1800 then
        local f=assert(io.open(os.getenv('A3_TEST_OUTPUT')..'/result.txt','w'))
        if message:find('REQUIRES 256K',1,true) then f:write('PASS 1 check: clear 256K requirement on a 128K machine\n')
        else f:write('FAIL missing 256K error screen: '..message..'\n') end
        f:close(); machine:exit()
    end
end,'frame')
