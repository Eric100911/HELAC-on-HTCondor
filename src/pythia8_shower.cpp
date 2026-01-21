/*
 * Standalone Pythia 8 Showering for LHE Events
 *
 * This program provides standalone Pythia 8 showering (not via cmsRun) with:
 * - Proper Upsilon decay settings (553, 100553, 200553 → μ+μ-)
 * - CP5 tuning by default
 * - Support for color octet states with HepMC output
 * - Phi-enriched mode with repeated showering
 *
 * Requirement: Standalone Pythia 8 implementation, not CMSSW's Pythia8 via cmsRun
 * Requirement: Upsilon mesons allowed to decay to μ+μ-
 * Requirement: Default tuning is CP5, or given by external input command
 */

#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <cstdlib>
#include <getopt.h>

// Pythia 8 headers
#include "Pythia8/Pythia.h"
#include "Pythia8/Pythia8ToHepMC.h"

// HepMC 2 headers
#include "HepMC/IO_GenEvent.h"
#include "HepMC/GenEvent.h"

using namespace Pythia8;

// Configuration structure
struct ShowerConfig {
    std::string inputLHE;
    std::string outputHepMC;
    std::string tuning = "CP5";  // Default: CP5
    std::string mode = "normal";  // normal, phi, color-octet
    int maxEvents = -1;  // -1 means all events
    int maxPhiAttempts = 100;  // For phi mode
    bool verbose = false;
    bool keepHepMC = true;
};

void printUsage(const char* progname) {
    std::cerr << "Standalone Pythia 8 Showering\n\n"
              << "Usage: " << progname << " [options]\n\n"
              << "Options:\n"
              << "  --input FILE       Input LHE file (required)\n"
              << "  --output FILE      Output HepMC file (required)\n"
              << "  --tune TUNE        Pythia tuning (default: CP5)\n"
              << "  --mode MODE        Shower mode: normal, phi, color-octet (default: normal)\n"
              << "  --max-events N     Maximum events to process (-1 = all)\n"
              << "  --max-phi-attempts N  Max attempts for phi mode (default: 100)\n"
              << "  --verbose          Enable verbose output\n"
              << "  --help, -h         Show this help\n\n"
              << "Supported tunings:\n"
              << "  CP5       - CUETP8M2T4 tune (Run 2 default)\n"
              << "  Monash2013 - Monash 2013 tune\n"
              << "  4C        - Tune 4C\n"
              << std::endl;
}

// Parse command line arguments
ShowerConfig parseArgs(int argc, char* argv[]) {
    ShowerConfig config;
    
    static struct option long_options[] = {
        {"input", required_argument, 0, 'i'},
        {"output", required_argument, 0, 'o'},
        {"tune", required_argument, 0, 't'},
        {"mode", required_argument, 0, 'm'},
        {"max-events", required_argument, 0, 'n'},
        {"max-phi-attempts", required_argument, 0, 'p'},
        {"verbose", no_argument, 0, 'v'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "i:o:t:m:n:p:vh", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'i':
                config.inputLHE = optarg;
                break;
            case 'o':
                config.outputHepMC = optarg;
                break;
            case 't':
                config.tuning = optarg;
                break;
            case 'm':
                config.mode = optarg;
                break;
            case 'n':
                config.maxEvents = std::atoi(optarg);
                break;
            case 'p':
                config.maxPhiAttempts = std::atoi(optarg);
                break;
            case 'v':
                config.verbose = true;
                break;
            case 'h':
                printUsage(argv[0]);
                exit(0);
            default:
                exit(1);
        }
    }
    
    if (config.inputLHE.empty() || config.outputHepMC.empty()) {
        std::cerr << "Error: Input and output files are required\n";
        printUsage(argv[0]);
        exit(1);
    }
    
    return config;
}

// Configure Pythia with proper settings
void configurePythia(Pythia& pythia, const ShowerConfig& config) {
    // Basic settings
    pythia.readString("Main:numberOfEvents = " + std::to_string(config.maxEvents));
    pythia.readString("Main:timesAllowErrors = 10");
    
    // LHE input
    pythia.readString("Beams:frameType = 4");
    pythia.readString("Beams:LHEF = " + config.inputLHE);
    
    // Apply tuning
    if (config.tuning == "CP5") {
        // CP5 tune settings
        pythia.readString("Tune:pp = 14");  // Monash 2013 as base
        pythia.readString("Tune:ee = 7");
        pythia.readString("MultipartonInteractions:pT0Ref = 2.4024");
        pythia.readString("MultipartonInteractions:ecmPow = 0.25208");
        pythia.readString("MultipartonInteractions:expPow = 1.6");
        pythia.readString("ColourReconnection:range = 5.176");
    } else if (config.tuning == "Monash2013") {
        pythia.readString("Tune:pp = 14");
    } else if (config.tuning == "4C") {
        pythia.readString("Tune:pp = 5");
    } else {
        std::cerr << "Warning: Unknown tuning '" << config.tuning 
                  << "', using Monash2013\n";
        pythia.readString("Tune:pp = 14");
    }
    
    // General showering settings
    pythia.readString("PartonLevel:MPI = on");
    pythia.readString("PartonLevel:ISR = on");
    pythia.readString("PartonLevel:FSR = on");
    pythia.readString("HadronLevel:Hadronize = on");
    pythia.readString("HadronLevel:Decay = on");
    
    // Upsilon decay settings (requirement: 553, 100553, 200553 → μ+μ-)
    pythia.readString("553:onMode = off");     // Upsilon(1S): turn off all decays
    pythia.readString("553:onIfMatch = 13 -13");  // Enable μ+μ- only
    pythia.readString("100553:onMode = off");  // Upsilon(2S)
    pythia.readString("100553:onIfMatch = 13 -13");
    pythia.readString("200553:onMode = off");  // Upsilon(3S)
    pythia.readString("200553:onIfMatch = 13 -13");
    
    // Mode-specific settings
    if (config.mode == "phi") {
        // Phi-enriched mode
        pythia.readString("333:mayDecay = off");  // Keep phi stable initially
        pythia.readString("StringFlav:mesonSvector = 0.4");  // Increase strangeness
        pythia.readString("StringFlav:probStoUD = 0.30");  // More s quarks
        pythia.readString("PhaseSpace:pTHatMin = 4.0");  // Higher pT cutoff
        std::cout << "Phi-enriched mode enabled\n";
    } else if (config.mode == "color-octet") {
        // Color octet mode - ensure color reconnection
        pythia.readString("ColourReconnection:reconnect = on");
        pythia.readString("ColourReconnection:mode = 1");
        std::cout << "Color-octet mode enabled\n";
    }
    
    // Process settings - read from LHE
    pythia.readString("ProcessLevel:all = off");
    
    if (config.verbose) {
        pythia.readString("Next:numberShowInfo = 1");
        pythia.readString("Next:numberShowProcess = 1");
        pythia.readString("Next:numberShowEvent = 1");
    } else {
        pythia.readString("Print:quiet = on");
    }
}

// Check if event contains hard phi meson
bool hasHardPhi(const Event& event, double minPt = 5.0) {
    for (int i = 0; i < event.size(); ++i) {
        if (event[i].idAbs() == 333 && event[i].pT() > minPt) {
            return true;
        }
    }
    return false;
}

// Main showering function
int runShowering(const ShowerConfig& config) {
    std::cout << "Standalone Pythia 8 Showering\n";
    std::cout << "  Input: " << config.inputLHE << "\n";
    std::cout << "  Output: " << config.outputHepMC << "\n";
    std::cout << "  Tuning: " << config.tuning << "\n";
    std::cout << "  Mode: " << config.mode << "\n";
    
    // Initialize Pythia
    Pythia pythia;
    configurePythia(pythia, config);
    
    if (!pythia.init()) {
        std::cerr << "Error: Pythia initialization failed\n";
        return 1;
    }
    
    // Setup HepMC output
    HepMC::IO_GenEvent hepmcOutput(config.outputHepMC, std::ios::out);
    Pythia8ToHepMC toHepMC;
    
    int nProcessed = 0;
    int nAccepted = 0;
    int nPhiAttempts = 0;
    
    // Event loop
    while (pythia.next()) {
        ++nProcessed;
        
        bool accept = true;
        
        // For phi mode, check if hard phi is present
        if (config.mode == "phi") {
            if (!hasHardPhi(pythia.event)) {
                ++nPhiAttempts;
                if (nPhiAttempts < config.maxPhiAttempts) {
                    accept = false;  // Reject and try again
                    continue;
                }
                // After max attempts, accept anyway
                nPhiAttempts = 0;
            } else {
                nPhiAttempts = 0;  // Reset counter on success
            }
        }
        
        if (accept) {
            // Convert to HepMC and write
            HepMC::GenEvent* hepmcEvent = new HepMC::GenEvent();
            toHepMC.fill_next_event(pythia, hepmcEvent);
            hepmcOutput << hepmcEvent;
            delete hepmcEvent;
            
            ++nAccepted;
        }
        
        // Progress reporting
        if (config.verbose && nProcessed % 1000 == 0) {
            std::cout << "Processed " << nProcessed << " events, accepted " 
                      << nAccepted << "\n";
        }
        
        // Check max events
        if (config.maxEvents > 0 && nAccepted >= config.maxEvents) {
            break;
        }
    }
    
    // Statistics
    pythia.stat();
    
    std::cout << "\nShowering completed:\n";
    std::cout << "  Events processed: " << nProcessed << "\n";
    std::cout << "  Events accepted: " << nAccepted << "\n";
    std::cout << "  Output: " << config.outputHepMC << "\n";
    
    return 0;
}

int main(int argc, char* argv[]) {
    try {
        ShowerConfig config = parseArgs(argc, argv);
        return runShowering(config);
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }
}
