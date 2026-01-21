/*
 * HepMC Event Mixer - Multi-source Event Combination
 * ===================================================
 *
 * Merges events from multiple HepMC3 input files into single combined events.
 * Supports 1 (passthrough), 2 (DPS), or 3+ (TPS/NPS) input sources.
 * Outputs HepMC2 format for CMSSW compatibility.
 *
 * Key features:
 * - Handles variable number of input sources (1 to N)
 * - Preserves particle barcodes with offsets to avoid conflicts
 * - Properly merges event weights
 * - Uses the source with fewer events as reference count
 *
 * Based on design from @Endymion2288/Full_MC_Production
 *
 * Compilation (in CMSSW environment with HepMC2 and HepMC3):
 *   g++ -std=c++17 -O2 hepmc_mixer.cpp -o hepmc_mixer \
 *       -I$HEPMC3/include -I$HEPMC2/include \
 *       -L$HEPMC3/lib64 -L$HEPMC2/lib \
 *       -Wl,-rpath,$HEPMC3/lib64 -Wl,-rpath,$HEPMC2/lib \
 *       -lHepMC3 -lHepMC
 *
 * Usage:
 *   ./hepmc_mixer output.hepmc input1.hepmc [input2.hepmc ...] [--nevents N]
 */

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <memory>
#include <map>
#include <algorithm>
#include <cstdlib>
#include <getopt.h>

// HepMC3 headers
#include "HepMC3/GenEvent.h"
#include "HepMC3/GenParticle.h"
#include "HepMC3/GenVertex.h"
#include "HepMC3/ReaderAscii.h"
#include "HepMC3/Print.h"

// HepMC2 headers  
#include "HepMC/GenEvent.h"
#include "HepMC/GenParticle.h"
#include "HepMC/GenVertex.h"
#include "HepMC/IO_GenEvent.h"

using namespace std;

/**
 * Convert single HepMC3 event to HepMC2 event
 * 
 * @param evt3 Input HepMC3 event
 * @param eventNumber Event number to assign
 * @param barcodeOffset Offset to add to all barcodes (to avoid conflicts)
 * @return Newly allocated HepMC2 event (caller owns)
 */
HepMC::GenEvent* convertToHepMC2(const HepMC3::GenEvent& evt3, 
                                  int eventNumber, 
                                  int barcodeOffset = 0) {
    HepMC::GenEvent* evt2 = new HepMC::GenEvent();
    evt2->set_event_number(eventNumber);
    evt2->set_signal_process_id(0);
    
    // Set weight
    if (evt3.weights().size() > 0) {
        evt2->weights().push_back(evt3.weights()[0]);
    } else {
        evt2->weights().push_back(1.0);
    }
    
    // Particle mapping: HepMC3 id -> HepMC2 particle
    map<int, HepMC::GenParticle*> particleMap;
    
    // Create all particles first
    for (const auto& p3 : evt3.particles()) {
        HepMC::FourVector mom(p3->momentum().px(), 
                              p3->momentum().py(),
                              p3->momentum().pz(),
                              p3->momentum().e());
        HepMC::GenParticle* p2 = new HepMC::GenParticle(mom, p3->pid(), p3->status());
        p2->suggest_barcode(p3->id() + barcodeOffset);
        particleMap[p3->id()] = p2;
    }
    
    // Create vertices and connect particles
    for (const auto& v3 : evt3.vertices()) {
        HepMC::FourVector pos(v3->position().x(),
                              v3->position().y(),
                              v3->position().z(),
                              v3->position().t());
        HepMC::GenVertex* v2 = new HepMC::GenVertex(pos);
        v2->suggest_barcode(v3->id() - barcodeOffset);
        
        // Add incoming particles
        for (const auto& p3_in : v3->particles_in()) {
            if (particleMap.count(p3_in->id())) {
                v2->add_particle_in(particleMap[p3_in->id()]);
            }
        }
        
        // Add outgoing particles
        for (const auto& p3_out : v3->particles_out()) {
            if (particleMap.count(p3_out->id())) {
                v2->add_particle_out(particleMap[p3_out->id()]);
            }
        }
        
        evt2->add_vertex(v2);
    }
    
    return evt2;
}

/**
 * Merge multiple HepMC3 events into one HepMC2 event
 * 
 * Used for DPS (2 sources) or TPS (3 sources) event generation.
 * 
 * @param events Vector of input HepMC3 events to merge
 * @param eventNumber Event number to assign to merged event
 * @return Newly allocated merged HepMC2 event (caller owns)
 */
HepMC::GenEvent* mergeEvents(const vector<HepMC3::GenEvent*>& events, int eventNumber) {
    HepMC::GenEvent* merged = new HepMC::GenEvent();
    merged->set_event_number(eventNumber);
    merged->set_signal_process_id(0);
    
    // Combine weights (product of all event weights)
    double combinedWeight = 1.0;
    for (const auto& evt : events) {
        if (evt && evt->weights().size() > 0) {
            combinedWeight *= evt->weights()[0];
        }
    }
    merged->weights().push_back(combinedWeight);
    
    // Barcode offset step to separate sources
    const int barcodeStep = 100000;
    
    // Process each source event
    for (size_t srcIdx = 0; srcIdx < events.size(); ++srcIdx) {
        if (!events[srcIdx]) continue;
        
        const HepMC3::GenEvent& evt = *events[srcIdx];
        int offset = static_cast<int>(srcIdx) * barcodeStep;
        
        // Particle mapping for this source
        map<int, HepMC::GenParticle*> particleMap;
        
        // Create particles with offset barcodes
        for (const auto& p3 : evt.particles()) {
            HepMC::FourVector mom(p3->momentum().px(), 
                                  p3->momentum().py(),
                                  p3->momentum().pz(),
                                  p3->momentum().e());
            HepMC::GenParticle* p2 = new HepMC::GenParticle(mom, p3->pid(), p3->status());
            p2->suggest_barcode(p3->id() + offset);
            particleMap[p3->id()] = p2;
        }
        
        // Create vertices and connect particles
        for (const auto& v3 : evt.vertices()) {
            HepMC::FourVector pos(v3->position().x(),
                                  v3->position().y(),
                                  v3->position().z(),
                                  v3->position().t());
            HepMC::GenVertex* v2 = new HepMC::GenVertex(pos);
            v2->suggest_barcode(v3->id() - offset);
            
            for (const auto& p3_in : v3->particles_in()) {
                if (particleMap.count(p3_in->id())) {
                    v2->add_particle_in(particleMap[p3_in->id()]);
                }
            }
            
            for (const auto& p3_out : v3->particles_out()) {
                if (particleMap.count(p3_out->id())) {
                    v2->add_particle_out(particleMap[p3_out->id()]);
                }
            }
            
            merged->add_vertex(v2);
        }
    }
    
    return merged;
}

/**
 * Print usage information
 */
void printUsage(const char* progname) {
    cerr << "HepMC Event Mixer - Multi-source Event Combination\n\n"
         << "Usage: " << progname << " output.hepmc input1.hepmc [input2.hepmc ...] [options]\n\n"
         << "Options:\n"
         << "  --nevents N, -n N    Maximum number of events to produce\n"
         << "  --help, -h           Show this help message\n\n"
         << "Examples:\n"
         << "  # Single source (passthrough with format conversion)\n"
         << "  " << progname << " output.hepmc input.hepmc\n\n"
         << "  # DPS: merge two sources\n"
         << "  " << progname << " dps_mixed.hepmc jpsi_shower.hepmc upsilon_shower.hepmc\n\n"
         << "  # TPS: merge three sources\n"
         << "  " << progname << " tps_mixed.hepmc jpsi1.hepmc jpsi2.hepmc gg.hepmc -n 10000\n"
         << endl;
}

int main(int argc, char* argv[]) {
    // Parse options
    int maxEvents = -1;  // -1 means no limit
    
    static struct option long_options[] = {
        {"nevents", required_argument, 0, 'n'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "n:h", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'n':
                maxEvents = atoi(optarg);
                break;
            case 'h':
                printUsage(argv[0]);
                return 0;
            default:
                return 1;
        }
    }
    
    // Remaining arguments are output file and input files
    vector<string> positionalArgs;
    for (int i = optind; i < argc; ++i) {
        positionalArgs.push_back(argv[i]);
    }
    
    if (positionalArgs.size() < 2) {
        cerr << "Error: Need at least output file and one input file\n";
        printUsage(argv[0]);
        return 1;
    }
    
    string outputFile = positionalArgs[0];
    vector<string> inputFiles(positionalArgs.begin() + 1, positionalArgs.end());
    
    size_t nSources = inputFiles.size();
    
    cout << "HepMC Event Mixer\n";
    cout << "  Output: " << outputFile << "\n";
    cout << "  Sources: " << nSources << "\n";
    for (size_t i = 0; i < inputFiles.size(); ++i) {
        cout << "    [" << i << "] " << inputFiles[i] << "\n";
    }
    if (maxEvents > 0) {
        cout << "  Max events: " << maxEvents << "\n";
    }
    
    // Open all input readers
    vector<unique_ptr<HepMC3::ReaderAscii>> readers;
    for (const auto& file : inputFiles) {
        auto reader = make_unique<HepMC3::ReaderAscii>(file);
        if (reader->failed()) {
            cerr << "Error: Cannot open input file: " << file << "\n";
            return 1;
        }
        readers.push_back(move(reader));
    }
    
    // Open output writer
    HepMC::IO_GenEvent writer(outputFile);
    
    // Read and merge events
    int eventCount = 0;
    vector<HepMC3::GenEvent> currentEvents(nSources);
    
    while (true) {
        // Check event limit
        if (maxEvents > 0 && eventCount >= maxEvents) {
            cout << "  Reached max events limit\n";
            break;
        }
        
        // Read one event from each source
        bool allOK = true;
        for (size_t i = 0; i < nSources; ++i) {
            currentEvents[i].clear();
            if (!readers[i]->read_event(currentEvents[i])) {
                allOK = false;
                break;
            }
        }
        
        if (!allOK) {
            // At least one source exhausted
            break;
        }
        
        // Create pointer vector for merging
        vector<HepMC3::GenEvent*> eventPtrs;
        for (auto& evt : currentEvents) {
            eventPtrs.push_back(&evt);
        }
        
        // Merge events
        HepMC::GenEvent* merged = mergeEvents(eventPtrs, eventCount);
        
        // Write to output
        writer.write_event(merged);
        
        delete merged;
        ++eventCount;
        
        if (eventCount % 1000 == 0) {
            cout << "  Processed " << eventCount << " events\r" << flush;
        }
    }
    
    cout << "\nMixing completed!\n";
    cout << "  Total events: " << eventCount << "\n";
    
    return 0;
}
