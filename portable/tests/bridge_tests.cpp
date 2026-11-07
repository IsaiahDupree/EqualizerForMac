#include "bridge.h"
#include <array>
#include <cmath>
#include <cstdlib>
#include <iostream>

void require(bool value, const char* message) {
    if (!value) { std::cerr << message << '\n'; std::exit(1); }
}
int main() {
    require(sonance_abi_version() == 1, "ABI version");
    require(sonance_band_v1_size() == sizeof(SonanceBandV1), "ABI struct layout");
    SonanceBandV1 band{0, 1000, 6, 1, 1, 12};
    const std::array<double, 3> frequencies{{20, 1000, 20000}};
    std::array<double, 3> response{{77, 77, 77}};
    char error[256]{};
    auto calculate = [&](int bypass) {
        return sonance_response_v1(&band, 1, 48000, -3, bypass, frequencies.data(), response.data(), 3, error, sizeof(error));
    };
    require(calculate(0) == 0, "native response succeeds");
    require(std::abs(response[1] - 3) < 1e-8, "actual core peaking gain plus preamp");
    require(calculate(1) == 0 && response[0] == 0 && response[1] == 0 && response[2] == 0, "bypass is flat");
    band.type = 99;
    response = {{77, 77, 77}};
    require(calculate(0) != 0 && error[0] != '\0', "invalid type reports an error");
    require(response[0] == 77 && response[1] == 77 && response[2] == 77, "invalid input preserves output");
    require(sonance_response_v1(nullptr, 1, 48000, 0, 0, frequencies.data(), response.data(), 3, error, 1) != 0 && error[0] == '\0', "bounded error output");
    require(sonance_response_v1(nullptr, 0, 48000, 0, 0, nullptr, response.data(), 3, nullptr, 0) != 0, "null input rejected");
    std::cout << "PASS: native ABI, real response, bypass and boundary checks\n";
}
