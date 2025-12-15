// Driver for using Pythia8 with lhe file to hep file

#include "Pythia8/Pythia.h"
#include "Pythia8Plugins/HepMC2.h"
#include "HepMC/GenEvent.h"
#include "HepMC/IO_GenEvent.h"
#include <exception>

using namespace Pythia8;

//==========================================================================

bool singleParticleFilter(const Event& event,
                          unsigned int pdgID,
                          double pTmin,
                          double etaMax) {
  bool found = false;
  for (int i = 0; i < event.size(); ++i) {
    const Particle& p = event[i];
    if (abs(p.id()) == pdgID) {
      if (p.pT() > pTmin && abs(p.eta()) < etaMax) {
        found = true;
        break;
      }
    }
  }
  return found;
}

int main() {
  Pythia pythia;

  string inputname="Pythia8_lhe.cmnd",outputname="Pythia8_lhe.hep";
  
  pythia.readFile(inputname.c_str());
  // Re-shower: disable hadronization.
  pythia.init();
  
  int nAbort=10;
  int nPrintLHA=1;
  int iAbort=0;
  int iPrintLHA=0;
  int iEventshower=pythia.mode("Main:spareMode1");
  int iEventShowerRepMax=pythia.mode("Main:spareMode2");
  int iEventShowerRepCnt=0;
  bool isValidEvent=false;

  int showerRepBins=pythia.mode("Main:spareMode3") + 1; // Including the overflow or fail bin.
  double showerRepMin=-0.5;
  double showerRepMax= iEventShowerRepMax * (showerRepBins) / (showerRepBins - 1) + showerRepMin; // Fail bin added.

  Hist iEventShowerRepCntHist("Number of re-shower attempts per event",
                             showerRepBins,showerRepMin,showerRepMax);

  HepMC::Pythia8ToHepMC ToHepMC;
  HepMC::IO_GenEvent ascii_io(outputname.c_str(), std::ios::out);

  for (int iEvent = 0; ; ++iEvent) {
    // cout << "[DEBUG] Begin with parton shower for event " << iEvent << endl;
    if (!pythia.next()) {
      if (++iAbort < nAbort) continue;
      break;
    }
    // try{
    //   if (!pythia.next()) {
    //     if (++iAbort < nAbort) continue;
    //     break;
    //   }
    // }
    // catch (std::exception& e) { 
    //   cerr << "Fatal error: " << e.what() << endl;
    //   if (++iAbort < nAbort) continue;
    //   break;
    // }
    // cout << "[DEBUG] Completed parton shower for event " << iEvent << endl;
    if (iEvent >= iEventshower) break;
    if (pythia.info.isLHA() && iPrintLHA < nPrintLHA) {
      pythia.LHAeventList();
      pythia.info.list();
      pythia.process.list();
      pythia.event.list();
      ++iPrintLHA;
    }
    // Re-shower: Core loop. Ensure phi(1020) has pT > 4 GeV and |eta| < 2.5
    iEventShowerRepCnt=0;
    isValidEvent=false;
    Event& event = pythia.event;
    Event savedPartonLevelEvent = event;
    // cout << "[DEBUG] Prepared to re-shower event "<< endl;
    while(iEventShowerRepMax <= 0 || iEventShowerRepCnt < iEventShowerRepMax) {
      ++iEventShowerRepCnt;
      // Re-shower: forceHadronLevel
      if (!pythia.forceHadronLevel(false)) continue;
      // try{
      //   if (!pythia.forceHadronLevel(false)) continue;
      // }
      // catch (std::exception& e) {
      //   cerr << "Fatal error during re-showering: " << e.what() << endl;
      //   continue;
      // }
      isValidEvent=singleParticleFilter(event,333,3.0,3.0);
      if (isValidEvent) break;
      // Re-shower: restore saved parton-level event.
      // if (iEventShowerRepCnt % 50 == 0) {
      //   cout << "[DEBUG] Re-shower attempt "<< iEventShowerRepCnt
      //        <<" for event "<< iEvent << endl;
      // }
      event = savedPartonLevelEvent;
    }
    iEventShowerRepCntHist.fill(iEventShowerRepCnt);
    if (!isValidEvent && iEventShowerRepMax > 0) {
      cout<<"Event "<< iEvent
             <<" failed to produce a valid phi(1020) after "
             << iEventShowerRepMax <<" attempts."
             << endl;
      continue;
    } else if (isValidEvent) {
      cout<<"Event "<< iEvent
             <<" produced a valid phi(1020) after "
             << iEventShowerRepCnt <<" attempts."
             << endl;
    }

    HepMC::GenEvent* hepmcevt = new HepMC::GenEvent();
    ToHepMC.fill_next_event(pythia, hepmcevt);

    ascii_io << hepmcevt;
    delete hepmcevt;
  }

  pythia.stat();
  cout << iEventShowerRepCntHist << endl;
  return 0;
}
  
