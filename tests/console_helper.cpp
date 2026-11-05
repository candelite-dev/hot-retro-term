#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>

// Native console I/O, independent of a shell's quoting and line discipline.
int main(int argc, char **argv)
{
    if (argc < 2) return 2;
    if (!std::strcmp(argv[1], "--wait")) {
        Sleep(INFINITE);
        return 0;
    }
    if (!std::strcmp(argv[1], "--tree")) {
        wchar_t path[MAX_PATH];
        GetModuleFileNameW(nullptr, path, MAX_PATH);
        wchar_t command[MAX_PATH + 32];
        swprintf_s(command, L"\"%s\" --wait", path);
        STARTUPINFOW startup {};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION child {};
        if (!CreateProcessW(nullptr, command, nullptr, nullptr, FALSE, 0,
                            nullptr, nullptr, &startup, &child)) return 3;
        std::printf("HRT_CHILD[%lu]\r\n", child.dwProcessId);
        std::fflush(stdout);
        CloseHandle(child.hThread);
        CloseHandle(child.hProcess);
        Sleep(INFINITE);
    }
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    if (!SetConsoleMode(input, ENABLE_VIRTUAL_TERMINAL_INPUT)) return 4;
    if (!std::strcmp(argv[1], "--resize")) {
        std::puts("HRT_RESIZE_READY");
        std::fflush(stdout);
        for (;;) {
            char trigger;
            DWORD count;
            if (!ReadFile(input, &trigger, 1, &count, nullptr) || count != 1) return 5;
            CONSOLE_SCREEN_BUFFER_INFO info {};
            if (!GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &info)) return 6;
            std::printf("HRT_SIZE[%d,%d]\r\n", info.srWindow.Right - info.srWindow.Left + 1,
                        info.srWindow.Bottom - info.srWindow.Top + 1);
            std::fflush(stdout);
        }
    } else if (!std::strcmp(argv[1], "--bytes") && argc == 3) {
        int remaining = std::atoi(argv[2]);
        std::puts("HRT_INPUT_READY");
        std::fflush(stdout);
        std::string hex;
        while (remaining > 0) {
            unsigned char byte;
            DWORD count;
            if (!ReadFile(input, &byte, 1, &count, nullptr) || count != 1) return 7;
            char encoded[3];
            sprintf_s(encoded, "%02x", unsigned(byte));
            hex += encoded;
            --remaining;
        }
        std::printf("HRT_INPUT_RESULT[%s]HRT_INPUT_DONE\r\n", hex.c_str());
    } else if (!std::strcmp(argv[1], "--output")) {
        for (int i = 0; i < 2048; ++i) std::puts("HRT_OUTPUT_LINE");
        std::puts("HRT_OUTPUT_DONE");
    } else return 8;
    std::fflush(stdout);
    // Keep the PTY alive so the test observes all output before tearing it down.
    Sleep(INFINITE);
}
