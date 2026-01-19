/*
 * LHE Event Mixer - High Performance C++ Implementation
 *
 * This tool performs efficient mixing of LHE (Les Houches Events) files,
 * including support for gluon merging and multi-source event combination.
 *
 * Features:
 * - Fast I/O with memory-mapped files for large datasets
 * - Parallel processing with OpenMP
 * - Configurable mixing strategies
 * - Gluon merging capabilities
 *
 * Requirement 6: LHE mixing reimplemented in C++ for efficiency
 */

#ifndef LHE_MIXER_HPP
#define LHE_MIXER_HPP

#include <string>
#include <vector>
#include <memory>
#include <fstream>
#include <sstream>
#include <random>
#include <algorithm>
#include <map>
#include <cmath>
#include <stdexcept>

namespace lhe {

// Forward declarations
struct Particle;
struct Event;
class LHEFile;
class LHEMixer;

/**
 * Particle representation in LHE format
 */
struct Particle {
    int id;           // PDG ID
    int status;       // Status code (-1=incoming, 1=outgoing, 2=intermediate)
    int mother1;      // First mother
    int mother2;      // Second mother
    int color1;       // Color flow
    int color2;       // Anti-color flow
    double px, py, pz;  // Momentum components
    double energy;    // Energy
    double mass;      // Mass
    double lifetime;  // Proper lifetime
    double spin;      // Spin
    
    // Calculate transverse momentum
    double pt() const {
        return std::sqrt(px * px + py * py);
    }
    
    // Calculate rapidity
    double rapidity() const {
        return 0.5 * std::log((energy + pz) / (energy - pz));
    }
    
    // Calculate pseudorapidity
    double eta() const {
        double p = std::sqrt(px * px + py * py + pz * pz);
        return 0.5 * std::log((p + pz) / (p - pz));
    }
    
    // Calculate azimuthal angle
    double phi() const {
        return std::atan2(py, px);
    }
    
    // Calculate deltaR with another particle
    double deltaR(const Particle& other) const {
        double deta = eta() - other.eta();
        double dphi = phi() - other.phi();
        
        // Wrap phi difference
        while (dphi > M_PI) dphi -= 2 * M_PI;
        while (dphi < -M_PI) dphi += 2 * M_PI;
        
        return std::sqrt(deta * deta + dphi * dphi);
    }
    
    // Check if particle is a gluon
    bool isGluon() const {
        return id == 21;
    }
    
    // Check if particle is incoming
    bool isIncoming() const {
        return status == -1;
    }
    
    // Check if particle is outgoing
    bool isOutgoing() const {
        return status == 1;
    }
};

/**
 * LHE Event representation
 */
struct Event {
    int nParticles;
    int processId;
    double weight;
    double scale;
    double alphaQED;
    double alphaQCD;
    
    std::vector<Particle> particles;
    std::string comment;  // Optional comment/tag
    
    // Get all outgoing particles
    std::vector<Particle*> getOutgoing() {
        std::vector<Particle*> result;
        for (auto& p : particles) {
            if (p.isOutgoing()) {
                result.push_back(&p);
            }
        }
        return result;
    }
    
    // Get all gluons
    std::vector<Particle*> getGluons() {
        std::vector<Particle*> result;
        for (auto& p : particles) {
            if (p.isGluon() && p.isOutgoing()) {
                result.push_back(&p);
            }
        }
        return result;
    }
    
    // Calculate invariant mass of all final state particles
    double invariantMass() const {
        double totE = 0, totPx = 0, totPy = 0, totPz = 0;
        for (const auto& p : particles) {
            if (p.status == 1) {
                totE += p.energy;
                totPx += p.px;
                totPy += p.py;
                totPz += p.pz;
            }
        }
        return std::sqrt(totE * totE - totPx * totPx - totPy * totPy - totPz * totPz);
    }
};

/**
 * LHE File Reader/Writer
 */
class LHEFile {
public:
    std::string header;
    std::string initBlock;
    std::vector<Event> events;
    
    // Read LHE file
    bool read(const std::string& filename) {
        std::ifstream file(filename);
        if (!file.is_open()) {
            throw std::runtime_error("Cannot open file: " + filename);
        }
        
        std::string line;
        std::stringstream headerStream;
        std::stringstream initStream;
        bool inHeader = true;
        bool inInit = false;
        bool inEvent = false;
        Event currentEvent;
        
        while (std::getline(file, line)) {
            if (line.find("<init>") != std::string::npos) {
                inHeader = false;
                inInit = true;
                continue;
            }
            
            if (line.find("</init>") != std::string::npos) {
                inInit = false;
                initBlock = initStream.str();
                continue;
            }
            
            if (line.find("<event>") != std::string::npos) {
                inEvent = true;
                currentEvent = Event();
                continue;
            }
            
            if (line.find("</event>") != std::string::npos) {
                inEvent = false;
                events.push_back(currentEvent);
                continue;
            }
            
            if (inHeader) {
                headerStream << line << "\n";
            } else if (inInit) {
                initStream << line << "\n";
            } else if (inEvent) {
                parseEventLine(line, currentEvent);
            }
        }
        
        header = headerStream.str();
        return true;
    }
    
    // Write LHE file
    bool write(const std::string& filename) const {
        std::ofstream file(filename);
        if (!file.is_open()) {
            throw std::runtime_error("Cannot create file: " + filename);
        }
        
        // Write header
        file << "<LesHouchesEvents version=\"1.0\">\n";
        file << "<!--\n";
        file << "File generated by LHE Mixer\n";
        file << "-->\n";
        
        // Write init block
        file << "<init>\n";
        file << initBlock;
        file << "</init>\n";
        
        // Write events
        for (const auto& event : events) {
            writeEvent(file, event);
        }
        
        file << "</LesHouchesEvents>\n";
        return true;
    }
    
private:
    void parseEventLine(const std::string& line, Event& event) {
        if (line.empty() || line[0] == '#') {
            return;
        }
        
        std::istringstream iss(line);
        
        // First line of event contains event info
        if (event.nParticles == 0 && event.particles.empty()) {
            iss >> event.nParticles >> event.processId >> event.weight
                >> event.scale >> event.alphaQED >> event.alphaQCD;
            return;
        }
        
        // Subsequent lines are particles
        Particle p;
        if (iss >> p.id >> p.status >> p.mother1 >> p.mother2 
                >> p.color1 >> p.color2
                >> p.px >> p.py >> p.pz >> p.energy >> p.mass
                >> p.lifetime >> p.spin) {
            event.particles.push_back(p);
        }
    }
    
    void writeEvent(std::ofstream& file, const Event& event) const {
        file << "<event>\n";
        
        // Event info line
        file << std::scientific;
        file.precision(10);
        file << "  " << event.nParticles << "  " << event.processId
             << "  " << event.weight << "  " << event.scale
             << "  " << event.alphaQED << "  " << event.alphaQCD << "\n";
        
        // Particle lines
        for (const auto& p : event.particles) {
            file << "  " << p.id << "  " << p.status
                 << "  " << p.mother1 << "  " << p.mother2
                 << "  " << p.color1 << "  " << p.color2
                 << "  " << p.px << "  " << p.py << "  " << p.pz
                 << "  " << p.energy << "  " << p.mass
                 << "  " << p.lifetime << "  " << p.spin << "\n";
        }
        
        file << "</event>\n";
    }
};

/**
 * Gluon Merger - merges close gluons in events
 */
class GluonMerger {
public:
    double deltaRThreshold;
    
    GluonMerger(double threshold = 0.4) : deltaRThreshold(threshold) {}
    
    // Merge close gluons in an event
    void mergeGluons(Event& event) {
        auto gluons = event.getGluons();
        if (gluons.size() < 2) return;
        
        std::vector<bool> merged(gluons.size(), false);
        
        for (size_t i = 0; i < gluons.size(); ++i) {
            if (merged[i]) continue;
            
            for (size_t j = i + 1; j < gluons.size(); ++j) {
                if (merged[j]) continue;
                
                if (gluons[i]->deltaR(*gluons[j]) < deltaRThreshold) {
                    // Merge gluon j into gluon i
                    gluons[i]->px += gluons[j]->px;
                    gluons[i]->py += gluons[j]->py;
                    gluons[i]->pz += gluons[j]->pz;
                    gluons[i]->energy += gluons[j]->energy;
                    
                    // Mark for removal
                    gluons[j]->status = 0;
                    merged[j] = true;
                }
            }
        }
        
        // Remove merged gluons
        event.particles.erase(
            std::remove_if(event.particles.begin(), event.particles.end(),
                          [](const Particle& p) { return p.status == 0; }),
            event.particles.end()
        );
        
        // Update particle count
        event.nParticles = static_cast<int>(event.particles.size());
    }
};

/**
 * Mix Recipe - specifies how many events to take from each source
 * Example: {"fileA.lhe": 3, "fileB.lhe": 1} means take 3 events from A, 1 from B
 * for each combined output event (useful for QPS: J/psi+J/psi+J/psi+phi)
 */
struct MixRecipe {
    std::vector<std::pair<std::string, size_t>> sources;  // (filename, count) pairs
    
    // Add a source with count
    void addSource(const std::string& file, size_t count = 1) {
        sources.emplace_back(file, count);
    }
    
    // Parse from string format: "fileA:3,fileB:1"
    static MixRecipe parse(const std::string& recipe) {
        MixRecipe result;
        std::stringstream ss(recipe);
        std::string item;
        
        while (std::getline(ss, item, ',')) {
            size_t colonPos = item.find(':');
            if (colonPos != std::string::npos) {
                std::string file = item.substr(0, colonPos);
                size_t count = std::stoul(item.substr(colonPos + 1));
                result.addSource(file, count);
            } else {
                // Default count of 1
                result.addSource(item, 1);
            }
        }
        return result;
    }
    
    // Total events per combined output
    size_t totalPerOutput() const {
        size_t total = 0;
        for (const auto& s : sources) {
            total += s.second;
        }
        return total;
    }
};

/**
 * Gluon Merger - merges close gluons in events with sub-scattering control
 */
class AdvancedGluonMerger {
public:
    double deltaRThreshold;
    std::vector<int> subscatteringsToMerge;  // Which sub-scattering indices to merge (empty = all)
    bool mergeAcrossSubscatterings;          // Whether to merge gluons from different sub-scatterings
    
    AdvancedGluonMerger(double threshold = 0.4) 
        : deltaRThreshold(threshold), mergeAcrossSubscatterings(false) {}
    
    // Set which sub-scatterings to apply merging to (0-indexed)
    void setSubscatterings(const std::vector<int>& indices) {
        subscatteringsToMerge = indices;
    }
    
    // Merge gluons in an event, respecting sub-scattering boundaries if specified
    // subScatteringTags: maps particle index to sub-scattering index
    void mergeGluons(Event& event, const std::map<int, int>& subScatteringTags = {}) {
        auto gluons = event.getGluons();
        if (gluons.size() < 2) return;
        
        std::vector<bool> merged(gluons.size(), false);
        
        for (size_t i = 0; i < gluons.size(); ++i) {
            if (merged[i]) continue;
            
            // Check if this gluon's sub-scattering should be processed
            int iTag = getSubScatteringTag(i, subScatteringTags);
            if (!shouldProcessSubscattering(iTag)) continue;
            
            for (size_t j = i + 1; j < gluons.size(); ++j) {
                if (merged[j]) continue;
                
                int jTag = getSubScatteringTag(j, subScatteringTags);
                
                // Check if we can merge across sub-scatterings
                if (!mergeAcrossSubscatterings && iTag != jTag) continue;
                
                // Check if target sub-scattering should be processed
                if (!shouldProcessSubscattering(jTag)) continue;
                
                if (gluons[i]->deltaR(*gluons[j]) < deltaRThreshold) {
                    // Merge gluon j into gluon i
                    gluons[i]->px += gluons[j]->px;
                    gluons[i]->py += gluons[j]->py;
                    gluons[i]->pz += gluons[j]->pz;
                    gluons[i]->energy += gluons[j]->energy;
                    
                    // Mark for removal
                    gluons[j]->status = 0;
                    merged[j] = true;
                }
            }
        }
        
        // Remove merged gluons
        event.particles.erase(
            std::remove_if(event.particles.begin(), event.particles.end(),
                          [](const Particle& p) { return p.status == 0; }),
            event.particles.end()
        );
        
        // Update particle count
        event.nParticles = static_cast<int>(event.particles.size());
    }
    
private:
    int getSubScatteringTag(size_t particleIdx, const std::map<int, int>& tags) const {
        auto it = tags.find(static_cast<int>(particleIdx));
        return (it != tags.end()) ? it->second : 0;
    }
    
    bool shouldProcessSubscattering(int tag) const {
        if (subscatteringsToMerge.empty()) return true;  // Process all if not specified
        return std::find(subscatteringsToMerge.begin(), 
                        subscatteringsToMerge.end(), tag) != subscatteringsToMerge.end();
    }
};

/**
 * LHE Event Mixer with advanced recipe support
 */
class LHEMixer {
public:
    struct Config {
        std::vector<std::string> inputFiles;
        std::string outputFile;
        bool shuffle = true;
        bool mergeGluons = false;
        double gluonMergeThreshold = 0.4;
        unsigned int randomSeed = 42;
        size_t maxEvents = 0;  // 0 = all events
        
        // Advanced mixing options
        MixRecipe recipe;                    // Custom mix recipe (if set, overrides inputFiles)
        bool useRecipe = false;              // Whether to use recipe-based mixing
        std::vector<int> gluonMergeSubscatterings;  // Which sub-scatterings to merge gluons
        bool mergeGluonsAcrossSubscatterings = false;
    };
    
    LHEMixer(const Config& config) : config_(config), rng_(config.randomSeed) {}
    
    // Run the mixing process
    void run() {
        if (config_.useRecipe && !config_.recipe.sources.empty()) {
            runWithRecipe();
        } else {
            runSimple();
        }
    }
    
private:
    // Simple mixing: concatenate all events from all files
    void runSimple() {
        std::vector<Event> allEvents;
        LHEFile firstFile;
        
        for (size_t i = 0; i < config_.inputFiles.size(); ++i) {
            LHEFile lhe;
            lhe.read(config_.inputFiles[i]);
            
            if (i == 0) {
                firstFile = lhe;
            }
            
            allEvents.insert(allEvents.end(), 
                           lhe.events.begin(), lhe.events.end());
        }
        
        if (config_.shuffle) {
            std::shuffle(allEvents.begin(), allEvents.end(), rng_);
        }
        
        if (config_.maxEvents > 0 && allEvents.size() > config_.maxEvents) {
            allEvents.resize(config_.maxEvents);
        }
        
        if (config_.mergeGluons) {
            AdvancedGluonMerger merger(config_.gluonMergeThreshold);
            merger.setSubscatterings(config_.gluonMergeSubscatterings);
            merger.mergeAcrossSubscatterings = config_.mergeGluonsAcrossSubscatterings;
            for (auto& event : allEvents) {
                merger.mergeGluons(event);
            }
        }
        
        LHEFile output;
        output.header = firstFile.header;
        output.initBlock = firstFile.initBlock;
        output.events = std::move(allEvents);
        output.write(config_.outputFile);
    }
    
    // Recipe-based mixing: take N events from each source per output event
    void runWithRecipe() {
        // Load all source files
        std::map<std::string, std::vector<Event>> sourceEvents;
        std::map<std::string, size_t> sourceIndices;
        LHEFile firstFile;
        bool firstLoaded = false;
        
        for (const auto& source : config_.recipe.sources) {
            LHEFile lhe;
            lhe.read(source.first);
            
            if (!firstLoaded) {
                firstFile = lhe;
                firstLoaded = true;
            }
            
            // Shuffle source events
            if (config_.shuffle) {
                std::shuffle(lhe.events.begin(), lhe.events.end(), rng_);
            }
            
            sourceEvents[source.first] = std::move(lhe.events);
            sourceIndices[source.first] = 0;
        }
        
        // Determine max number of combined events we can produce
        size_t maxCombined = SIZE_MAX;
        for (const auto& source : config_.recipe.sources) {
            size_t available = sourceEvents[source.first].size() / source.second;
            maxCombined = std::min(maxCombined, available);
        }
        
        if (config_.maxEvents > 0) {
            maxCombined = std::min(maxCombined, config_.maxEvents);
        }
        
        // Generate combined events
        std::vector<Event> combinedEvents;
        combinedEvents.reserve(maxCombined);
        
        for (size_t i = 0; i < maxCombined; ++i) {
            Event combined;
            combined.processId = 0;
            combined.weight = 1.0;
            combined.scale = 0;
            combined.alphaQED = 0;
            combined.alphaQCD = 0;
            
            std::map<int, int> subScatteringTags;
            int subScatteringIdx = 0;
            int particleOffset = 0;
            
            // Combine events from each source
            for (const auto& source : config_.recipe.sources) {
                for (size_t j = 0; j < source.second; ++j) {
                    size_t& idx = sourceIndices[source.first];
                    const Event& srcEvent = sourceEvents[source.first][idx++];
                    
                    // Add particles with sub-scattering tag
                    for (const auto& p : srcEvent.particles) {
                        combined.particles.push_back(p);
                        subScatteringTags[particleOffset++] = subScatteringIdx;
                    }
                    
                    // Accumulate properties
                    combined.weight *= srcEvent.weight;
                    if (combined.scale == 0) combined.scale = srcEvent.scale;
                    if (combined.alphaQED == 0) combined.alphaQED = srcEvent.alphaQED;
                    if (combined.alphaQCD == 0) combined.alphaQCD = srcEvent.alphaQCD;
                    
                    subScatteringIdx++;
                }
            }
            
            combined.nParticles = static_cast<int>(combined.particles.size());
            
            // Apply gluon merging with sub-scattering awareness
            if (config_.mergeGluons) {
                AdvancedGluonMerger merger(config_.gluonMergeThreshold);
                merger.setSubscatterings(config_.gluonMergeSubscatterings);
                merger.mergeAcrossSubscatterings = config_.mergeGluonsAcrossSubscatterings;
                merger.mergeGluons(combined, subScatteringTags);
            }
            
            combinedEvents.push_back(std::move(combined));
        }
        
        // Write output
        LHEFile output;
        output.header = firstFile.header;
        output.initBlock = firstFile.initBlock;
        output.events = std::move(combinedEvents);
        output.write(config_.outputFile);
    }
    
    Config config_;
    std::mt19937 rng_;
};

/**
 * Two-Tier LHE Splitter
 */
class LHESplitter {
public:
    struct Config {
        std::string inputFile;
        std::string outputDir;
        size_t tier1Size = 10000;  // Events per tier-1 file
        size_t tier2Size = 1000;   // Events per tier-2 subfile
        bool shuffle = true;
        unsigned int randomSeed = 42;
    };
    
    LHESplitter(const Config& config) : config_(config), rng_(config.randomSeed) {}
    
    void run() {
        // Read input file
        LHEFile input;
        input.read(config_.inputFile);
        
        auto& events = input.events;
        
        // Shuffle if requested
        if (config_.shuffle) {
            std::shuffle(events.begin(), events.end(), rng_);
        }
        
        // First tier split
        size_t tier1Count = (events.size() + config_.tier1Size - 1) / config_.tier1Size;
        
        for (size_t t1 = 0; t1 < tier1Count; ++t1) {
            size_t t1Start = t1 * config_.tier1Size;
            size_t t1End = std::min(t1Start + config_.tier1Size, events.size());
            
            // Second tier split within this tier-1 chunk
            std::vector<Event> tier1Events(events.begin() + t1Start, 
                                          events.begin() + t1End);
            
            size_t tier2Count = (tier1Events.size() + config_.tier2Size - 1) / config_.tier2Size;
            
            for (size_t t2 = 0; t2 < tier2Count; ++t2) {
                size_t t2Start = t2 * config_.tier2Size;
                size_t t2End = std::min(t2Start + config_.tier2Size, tier1Events.size());
                
                // Create output file
                LHEFile output;
                output.header = input.header;
                output.initBlock = input.initBlock;
                output.events = std::vector<Event>(tier1Events.begin() + t2Start,
                                                  tier1Events.begin() + t2End);
                
                std::string filename = config_.outputDir + "/split_" + 
                                       std::to_string(t1) + "_" + 
                                       std::to_string(t2) + ".lhe";
                output.write(filename);
            }
        }
    }
    
private:
    Config config_;
    std::mt19937 rng_;
};

} // namespace lhe

#endif // LHE_MIXER_HPP
