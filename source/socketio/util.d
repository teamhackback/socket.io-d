module socketio.util;

char toChar()(size_t i)
{
    if(i <= 9)
        return cast(char)('0' + i);
    else
        return cast(char)('a' + (i-10));
}

string generateId()()
{
    import std.exception : assumeUnique;
    import std.uuid : randomUUID;

    auto result = new char[32];
    auto uuid = randomUUID();
    size_t i = 0;
    foreach(entry; uuid.data)
    {
        const size_t hi = (entry >> 4) & 0x0F;
        result[i++] = hi.toChar;

        const size_t lo = (entry) & 0x0F;
        result[i++] = lo.toChar;
    }
    return result.assumeUnique;
}
