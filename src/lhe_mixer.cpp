/*
 * LHE Mixer - Command Line Interface
 *
 * High-performance C++ implementation for LHE event mixing,
 * splitting, shuffling, and gluon merging operations.
 *
 * Usage:
 *   lhe_mixer mix --inputs file1.lhe,file2.lhe --output mixed.lhe [--shuffle]
 *   lhe_mixer split --input large.lhe --output-dir split/ --tier1 10000 --tier2 1000
 *   lhe_mixer merge-gluons --input events.lhe --output merged.lhe --delta-r 0.4
 */

#include "lhe_mixer.hpp"
#include <iostream>
#include <fstream>
#include <sstream>
#include <getopt.h>
#include <cstdlib>
#include <sys/stat.h>
#include <unistd.h>

using namespace lhe;

// Print usage information
void printUsage(const char* progname) {
    std::cerr << "LHE Mixer - High Performance Event Processing\n\n"
              << "Usage: " << progname << " <command> [options]\n\n"
              << "Commands:\n"
              << "  mix           Mix events from multiple LHE files\n"
              << "  split         Two-tier split and shuffle of LHE file\n"
              << "  merge-gluons  Merge close gluons in events\n"
              << "  info          Display LHE file information\n\n"
              << "Options:\n"
              << "  --inputs, -i FILE[,FILE,...]  Input LHE files (comma-separated)\n"
              << "  --input FILE                   Single input file\n"
              << "  --output, -o FILE             Output file\n"
              << "  --output-dir DIR              Output directory (for split)\n"
              << "  --shuffle                     Shuffle events\n"
              << "  --merge-gluons                Enable gluon merging\n"
              << "  --delta-r VALUE               Delta R threshold for merging (default: 0.4)\n"
              << "  --tier1 N                     Tier-1 split size (default: 10000)\n"
              << "  --tier2 N                     Tier-2 split size (default: 1000)\n"
              << "  --max-events N                Maximum events to process (0 = all)\n"
              << "  --seed N                      Random seed (default: 42)\n"
              << "  --config FILE                 Load options from JSON config file\n"
              << "  --help, -h                    Show this help message\n"
              << std::endl;
}

// Split comma-separated string into vector
std::vector<std::string> splitString(const std::string& str, char delim = ',') {
    std::vector<std::string> result;
    std::stringstream ss(str);
    std::string item;
    while (std::getline(ss, item, delim)) {
        if (!item.empty()) {
            result.push_back(item);
        }
    }
    return result;
}

// Create directory if it doesn't exist
bool ensureDirectory(const std::string& path) {
    struct stat st;
    if (stat(path.c_str(), &st) == 0) {
        return S_ISDIR(st.st_mode);
    }
    return mkdir(path.c_str(), 0755) == 0;
}

// Command: mix
int cmdMix(int argc, char* argv[]) {
    LHEMixer::Config config;
    
    static struct option long_options[] = {
        {"inputs", required_argument, 0, 'i'},
        {"output", required_argument, 0, 'o'},
        {"shuffle", no_argument, 0, 's'},
        {"merge-gluons", no_argument, 0, 'g'},
        {"delta-r", required_argument, 0, 'r'},
        {"max-events", required_argument, 0, 'n'},
        {"seed", required_argument, 0, 'S'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "i:o:sgr:n:S:h", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'i':
                config.inputFiles = splitString(optarg);
                break;
            case 'o':
                config.outputFile = optarg;
                break;
            case 's':
                config.shuffle = true;
                break;
            case 'g':
                config.mergeGluons = true;
                break;
            case 'r':
                config.gluonMergeThreshold = std::stod(optarg);
                break;
            case 'n':
                config.maxEvents = std::stoul(optarg);
                break;
            case 'S':
                config.randomSeed = std::stoul(optarg);
                break;
            case 'h':
                printUsage("lhe_mixer mix");
                return 0;
            default:
                return 1;
        }
    }
    
    if (config.inputFiles.empty()) {
        std::cerr << "Error: No input files specified\n";
        return 1;
    }
    
    if (config.outputFile.empty()) {
        std::cerr << "Error: No output file specified\n";
        return 1;
    }
    
    std::cout << "LHE Mixer - Mixing " << config.inputFiles.size() << " files\n";
    std::cout << "  Output: " << config.outputFile << "\n";
    std::cout << "  Shuffle: " << (config.shuffle ? "yes" : "no") << "\n";
    std::cout << "  Merge gluons: " << (config.mergeGluons ? "yes" : "no") << "\n";
    
    try {
        LHEMixer mixer(config);
        mixer.run();
        std::cout << "Mixing completed successfully!\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}

// Command: split
int cmdSplit(int argc, char* argv[]) {
    LHESplitter::Config config;
    
    static struct option long_options[] = {
        {"input", required_argument, 0, 'i'},
        {"output-dir", required_argument, 0, 'o'},
        {"tier1", required_argument, 0, '1'},
        {"tier2", required_argument, 0, '2'},
        {"shuffle", no_argument, 0, 's'},
        {"seed", required_argument, 0, 'S'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "i:o:1:2:sS:h", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'i':
                config.inputFile = optarg;
                break;
            case 'o':
                config.outputDir = optarg;
                break;
            case '1':
                config.tier1Size = std::stoul(optarg);
                break;
            case '2':
                config.tier2Size = std::stoul(optarg);
                break;
            case 's':
                config.shuffle = true;
                break;
            case 'S':
                config.randomSeed = std::stoul(optarg);
                break;
            case 'h':
                printUsage("lhe_mixer split");
                return 0;
            default:
                return 1;
        }
    }
    
    if (config.inputFile.empty()) {
        std::cerr << "Error: No input file specified\n";
        return 1;
    }
    
    if (config.outputDir.empty()) {
        config.outputDir = ".";
    }
    
    if (!ensureDirectory(config.outputDir)) {
        std::cerr << "Error: Cannot create output directory: " << config.outputDir << "\n";
        return 1;
    }
    
    std::cout << "LHE Splitter - Two-tier split\n";
    std::cout << "  Input: " << config.inputFile << "\n";
    std::cout << "  Output dir: " << config.outputDir << "\n";
    std::cout << "  Tier-1 size: " << config.tier1Size << "\n";
    std::cout << "  Tier-2 size: " << config.tier2Size << "\n";
    std::cout << "  Shuffle: " << (config.shuffle ? "yes" : "no") << "\n";
    
    try {
        LHESplitter splitter(config);
        splitter.run();
        std::cout << "Splitting completed successfully!\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}

// Command: merge-gluons
int cmdMergeGluons(int argc, char* argv[]) {
    std::string inputFile;
    std::string outputFile;
    double deltaR = 0.4;
    
    static struct option long_options[] = {
        {"input", required_argument, 0, 'i'},
        {"output", required_argument, 0, 'o'},
        {"delta-r", required_argument, 0, 'r'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "i:o:r:h", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'i':
                inputFile = optarg;
                break;
            case 'o':
                outputFile = optarg;
                break;
            case 'r':
                deltaR = std::stod(optarg);
                break;
            case 'h':
                printUsage("lhe_mixer merge-gluons");
                return 0;
            default:
                return 1;
        }
    }
    
    if (inputFile.empty()) {
        std::cerr << "Error: No input file specified\n";
        return 1;
    }
    
    if (outputFile.empty()) {
        std::cerr << "Error: No output file specified\n";
        return 1;
    }
    
    std::cout << "LHE Gluon Merger\n";
    std::cout << "  Input: " << inputFile << "\n";
    std::cout << "  Output: " << outputFile << "\n";
    std::cout << "  Delta R threshold: " << deltaR << "\n";
    
    try {
        // Read input file
        LHEFile lhe;
        lhe.read(inputFile);
        
        std::cout << "  Events read: " << lhe.events.size() << "\n";
        
        // Merge gluons in each event
        GluonMerger merger(deltaR);
        size_t mergedCount = 0;
        
        for (auto& event : lhe.events) {
            size_t before = event.particles.size();
            merger.mergeGluons(event);
            if (event.particles.size() < before) {
                ++mergedCount;
            }
        }
        
        std::cout << "  Events with merged gluons: " << mergedCount << "\n";
        
        // Write output
        lhe.write(outputFile);
        std::cout << "Gluon merging completed successfully!\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}

// Command: info
int cmdInfo(int argc, char* argv[]) {
    if (argc < 1) {
        std::cerr << "Usage: lhe_mixer info <file.lhe>\n";
        return 1;
    }
    
    std::string inputFile = argv[0];
    
    try {
        LHEFile lhe;
        lhe.read(inputFile);
        
        std::cout << "LHE File Information\n";
        std::cout << "  File: " << inputFile << "\n";
        std::cout << "  Events: " << lhe.events.size() << "\n";
        
        if (!lhe.events.empty()) {
            const auto& first = lhe.events.front();
            std::cout << "  First event:\n";
            std::cout << "    Particles: " << first.particles.size() << "\n";
            std::cout << "    Process ID: " << first.processId << "\n";
            std::cout << "    Weight: " << first.weight << "\n";
            std::cout << "    Scale: " << first.scale << "\n";
            
            // Count particle types
            int nIncoming = 0, nOutgoing = 0, nGluons = 0;
            for (const auto& p : first.particles) {
                if (p.isIncoming()) ++nIncoming;
                if (p.isOutgoing()) ++nOutgoing;
                if (p.isGluon()) ++nGluons;
            }
            std::cout << "    Incoming: " << nIncoming << "\n";
            std::cout << "    Outgoing: " << nOutgoing << "\n";
            std::cout << "    Gluons: " << nGluons << "\n";
        }
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}

// Main entry point
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printUsage(argv[0]);
        return 1;
    }
    
    std::string command = argv[1];
    
    // Shift arguments
    argc -= 2;
    argv += 2;
    
    if (command == "mix") {
        return cmdMix(argc, argv);
    } else if (command == "split") {
        return cmdSplit(argc, argv);
    } else if (command == "merge-gluons") {
        return cmdMergeGluons(argc, argv);
    } else if (command == "info") {
        return cmdInfo(argc, argv);
    } else if (command == "--help" || command == "-h") {
        printUsage(argv[0]);
        return 0;
    } else {
        std::cerr << "Unknown command: " << command << "\n";
        printUsage(argv[0]);
        return 1;
    }
}
