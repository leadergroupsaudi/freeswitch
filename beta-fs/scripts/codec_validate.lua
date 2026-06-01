--codec_validate.lua
local codecdet = session:getVariable("isvideocall");
freeswitch.consoleLog("notice","Codec Details variable Tyoe ::".. type(codecdet));
freeswitch.consoleLog("notice","Is Video Call ::"..codecdet);
if codecdet == "true" then
        session:setVariable("avformat", "mp4");
else
        session:setVariable("avformat", "wav");
end
