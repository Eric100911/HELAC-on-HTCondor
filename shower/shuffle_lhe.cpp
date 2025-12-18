#include <algorithm> // for std::shuffle
#include <fstream>
#include <iostream>
#include <random> // for std::default_random_engine, std::random_device
#include <string>
#include <vector>

// Enum to keep track of where we are in the file
enum State { HEADER, EVENT, BETWEEN_EVENTS, FOOTER };

int main(int argc, char *argv[]) {
  // 1. Argument Checking
  if (argc != 3) {
    std::cerr << "Usage: " << argv[0] << " <input_file.lhe> <output_file.lhe>"
              << std::endl;
    return 1;
  }

  std::string inputPath = argv[1];
  std::string outputPath = argv[2];

  std::ifstream inFile(inputPath);
  if (!inFile.is_open()) {
    std::cerr << "Error: Could not open input file " << inputPath << std::endl;
    return 1;
  }

  // 2. Data Containers
  std::string header = "";
  std::vector<std::string> events;
  std::string footer = "";

  std::string line;
  std::string currentEventBlock = "";
  State currentState = HEADER;

  // 3. Parsing Loop
  while (std::getline(inFile, line)) {

    // Check for state transitions based on tags
    // Note: We use .find() to handle potential indentation/whitespace
    bool isEventStart = (line.find("<event>") != std::string::npos);
    bool isEventEnd = (line.find("</event>") != std::string::npos);
    bool isFileEnd = (line.find("</LesHouchesEvents>") != std::string::npos);

    switch (currentState) {
    case HEADER:
      if (isEventStart) {
        currentState = EVENT;
        currentEventBlock += line + "\n";
      } else {
        header += line + "\n";
      }
      break;

    case EVENT:
      currentEventBlock += line + "\n";
      if (isEventEnd) {
        events.push_back(currentEventBlock);
        currentEventBlock = ""; // Reset buffer
        currentState = BETWEEN_EVENTS;
      }
      break;

    case BETWEEN_EVENTS:
      if (isEventStart) {
        currentState = EVENT;
        currentEventBlock += line + "\n";
      } else if (isFileEnd) {
        currentState = FOOTER;
        footer += line + "\n";
      } else {
        // Usually whitespace between events.
        // We ignore it to ensure a clean output file,
        // or you can append it to the footer if you prefer.
      }
      break;

    case FOOTER:
      footer += line + "\n";
      break;
    }
  }
  inFile.close();

  std::cout << "Parsed " << events.size() << " events." << std::endl;

  // 4. Shuffling
  std::cout << "Shuffling events..." << std::endl;
  std::random_device rd;
  std::mt19937 g(rd());
  std::shuffle(events.begin(), events.end(), g);

  // 5. Writing Output
  std::ofstream outFile(outputPath);
  if (!outFile.is_open()) {
    std::cerr << "Error: Could not create output file " << outputPath
              << std::endl;
    return 1;
  }

  // Write Header
  outFile << header;

  // Write Shuffled Events
  for (const auto &eventStr : events) {
    outFile << eventStr;
  }

  // Write Footer
  outFile << footer;

  outFile.close();
  std::cout << "Successfully wrote shuffled data to " << outputPath
            << std::endl;

  return 0;
}