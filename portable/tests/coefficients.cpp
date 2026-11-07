#include <sonance/eq.hpp>

#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>

int main() {
    const std::array<std::string, 8> names{{
        "peaking", "lowShelf", "highShelf", "lowPass", "highPass", "notch", "bandPass", "allPass"}};
    std::cout << std::setprecision(17);
    std::string line;
    try {
        while (std::getline(std::cin, line)) {
            std::istringstream input(line);
            std::string name, extra;
            double rate;
            sonance::Band band;
            if (!(input >> name >> rate >> band.frequency >> band.gain_db >> band.q >> band.slope_db_per_oct) ||
                (input >> extra)) throw std::invalid_argument("invalid coefficient request");
            std::size_t index = 0;
            while (index < names.size() && names[index] != name) ++index;
            if (index == names.size()) throw std::invalid_argument("unknown filter");
            band.type = static_cast<sonance::FilterType>(index);
            const auto config = sonance::Configuration::prepare(&band, 1, rate);
            std::cout << '[';
            for (std::size_t s = 0; s < config.section_count(); ++s) {
                const auto& c = config.section(s);
                if (s) std::cout << ',';
                std::cout << '[' << c.b0 << ',' << c.b1 << ',' << c.b2 << ',' << c.a1 << ',' << c.a2 << ']';
            }
            std::cout << "]\n";
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
