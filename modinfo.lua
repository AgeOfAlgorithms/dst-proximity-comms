local zh = locale == "zh" or locale == "zhr" or locale == "zht"
local ru = locale == "ru"

name = "Proximity Comms (Text and Voice Chat)"
author = "AgeOfAlgorithms"
version = "0.2.0"
api_version = 10
dst_compatible = true
all_clients_require_mod = true
client_only_mod = false
priority = 0
icon_atlas = "modicon.xml"
icon = "modicon.tex"
server_filter_tags = {"proximity chat", "voice chat", "translation"}

if zh then
    description = [[近距离聊天：悄悄话、说话和大喊只有附近的玩家能看到（远一点只看得到模糊的字），全体照旧。气泡会滚动长句，说话者在屏幕外时贴在屏幕边缘。手柄：命令轮盘里的“快捷聊天”。

配合免费程序 Koetama（github.com/AgeOfAlgorithms/koetama）：近距离语音聊天、实时字幕和离线翻译。没有 Koetama 也能完整使用文字聊天。

本模组只与本机的 Koetama 通信（127.0.0.1）。Koetama 通过中继端到端加密传送语音。

命令：/s /y /w /g，/pc help]]
elseif ru then
    description = [[Чат рядом: шёпот, речь и крик видят только игроки поблизости (чуть дальше — неразборчивые буквы), «всем» — как в игре. Длинные реплики прокручиваются, реплики говорящих за краем экрана прижимаются к краю. Геймпад: «Быстрый чат» в колесе команд.

С бесплатной программой Koetama (github.com/AgeOfAlgorithms/koetama): голосовой чат рядом, живые субтитры и офлайн-перевод. Без неё текстовый чат работает полностью.

Мод общается только с Koetama на этом ПК (127.0.0.1). Koetama передаёт голоса со сквозным шифрованием через ретранслятор.

Команды: /s /y /w /g, /pc help]]
else
    description = [[Proximity chat: Whisper, Speak and Yell reach only the players near you (a bit farther, garbled letters), Global works as always. Long lines scroll in their bubbles, and the bubble of a speaker off screen sits on the screen edge. Controller: "Quick chat" in the command wheel.

With the free Koetama app (github.com/AgeOfAlgorithms/koetama): proximity voice chat, live captions and offline translation. Without it the text chat works fully.

This mod talks only to Koetama on your own PC (127.0.0.1). Koetama sends voices end-to-end encrypted through a relay.

Commands: /s /y /w /g, /pc help]]
end

local function tiles(from, to, step)
    local out = {}
    for t = from, to, step do out[#out + 1] = {description = t .. (zh and " 格" or (ru and " клеток" or " tiles")), data = t} end
    return out
end

configuration_options = {
    {
        name = "whisper_range",
        label = zh and "悄悄话距离" or (ru and "Дальность шёпота" or "Whisper range"),
        hover = zh and "悄悄话的字在多远内看得清（再远 40% 是模糊的字）。总是比说话近。" or (ru and "Насколько далеко разборчив шёпот (ещё на 40% дальше — неразборчиво). Всегда ближе речи." or "How far Whisper's words are clear (40% farther: garbled). Always shorter than Speak."),
        options = tiles(2, 16, 1),
        default = 8,
    },
    {
        name = "speak_range",
        label = zh and "说话距离" or (ru and "Дальность речи" or "Speak range"),
        hover = zh and "说话的字在多远内看得清（再远 40% 是模糊的字）。" or (ru and "Насколько далеко разборчива речь (ещё на 40% дальше — неразборчиво)." or "How far Speak's words are clear (40% farther: garbled)."),
        options = tiles(4, 40, 1),
        default = 18,
    },
    {
        name = "yell_range",
        label = zh and "大喊距离" or (ru and "Дальность крика" or "Yell range"),
        hover = zh and "大喊的字在多远内看得清（再远 37.5% 是模糊的字）。总是比说话远。" or (ru and "Насколько далеко разборчив крик (ещё на 37,5% дальше — неразборчиво). Всегда дальше речи." or "How far Yell's words are clear (37.5% farther: garbled). Always farther than Speak."),
        options = tiles(8, 64, 2),
        default = 32,
    },
    {
        name = "voice",
        label = zh and "语音聊天（Koetama）" or (ru and "Голосовой чат (Koetama)" or "Voice chat (Koetama)"),
        hover = zh and "关闭：只有文字（字幕和翻译仍然可用）。" or (ru and "Выкл: только текст (субтитры и перевод остаются)." or "Off: text only (captions and translation still work)."),
        options = {
            {description = zh and "开" or (ru and "Вкл" or "On"), data = true},
            {description = zh and "关" or (ru and "Выкл" or "Off"), data = false},
        },
        default = true,
    },
    {
        name = "voice_region",
        label = zh and "语音服务器区域" or (ru and "Регион голосового сервера" or "Voice server region"),
        hover = zh and "自动：第一个玩家附近。" or (ru and "Авто: рядом с первым игроком." or "Auto: near the first player."),
        options = {
            {description = zh and "自动" or (ru and "Авто" or "Auto"), data = ""},
            {description = "North America (west)", data = "wnam"},
            {description = "North America (east)", data = "enam"},
            {description = "South America", data = "sam"},
            {description = "Europe (west)", data = "weur"},
            {description = "Europe (east)", data = "eeur"},
            {description = "Asia-Pacific", data = "apac"},
            {description = "Asia (north-east)", data = "apac-ne"},
            {description = "Asia (south-east)", data = "apac-se"},
            {description = "Oceania", data = "oc"},
            {description = "Africa", data = "afr"},
            {description = "Middle East", data = "me"},
        },
        default = "",
    },
}
