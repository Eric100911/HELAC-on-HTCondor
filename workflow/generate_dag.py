#!/usr/bin/env python3
"""
DAGman Workflow Generator

Generates a complete DAGman workflow based on the YAML configuration file.
This creates the DAG file and all necessary job submission files for the
entire MC simulation pipeline.
"""

import argparse
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)


class DAGmanGenerator:
    """Generate DAGman workflows for MC simulation pipeline."""
    
    def __init__(self, config_path: str, output_dir: str = "workflow"):
        """Initialize with configuration file."""
        self.config_path = config_path
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)
        
        self.dag_lines = []
        self.sub_files = {}
        
    def generate(self) -> str:
        """Generate complete DAGman workflow."""
        workflow_name = self.config.get('workflow', {}).get('name', 'mc_workflow')
        
        self.dag_lines = [
            f"# DAGman workflow: {workflow_name}",
            f"# Generated automatically from {self.config_path}",
            "",
            "# Configuration",
            "CONFIG config/dagman.config",
            "",
        ]
        
        # Generate nodes for each stage
        self._generate_matrix_element_nodes()
        self._generate_preprocessing_nodes()
        self._generate_showering_nodes()
        self._generate_simulation_nodes()
        self._generate_cleanup_nodes()
        
        # Write DAG file
        dag_content = "\n".join(self.dag_lines)
        dag_path = self.output_dir / "generated.dag"
        
        with open(dag_path, 'w') as f:
            f.write(dag_content)
        
        # Write submission files
        self._write_submit_files()
        
        # Write DAGman config
        self._write_dagman_config()
        
        return str(dag_path)
    
    def _generate_matrix_element_nodes(self):
        """Generate matrix element generation nodes."""
        me_config = self.config.get('matrix_element', {})
        
        if not me_config.get('generator'):
            return
            
        self.dag_lines.append("# Matrix Element Generation")
        
        seeds = me_config.get('seeds', {})
        start_seed = seeds.get('start', 11)
        end_seed = seeds.get('end', 20)
        
        batch_mode = me_config.get('batch_mode', 'single_job')
        
        if batch_mode == 'single_job':
            # Single job processes all seeds (requirement 1)
            self.dag_lines.append(f"JOB matrix_element matrix_element.sub")
            self.dag_lines.append(f"VARS matrix_element seeds=\"{start_seed}-{end_seed}\"")
            self.dag_lines.append(f"RETRY matrix_element 3")
            self.dag_lines.append("")
            
            self._create_matrix_element_sub(me_config, start_seed, end_seed)
        else:
            # Individual jobs per seed
            for seed in range(start_seed, end_seed + 1):
                node_name = f"matrix_element_{seed}"
                self.dag_lines.append(f"JOB {node_name} matrix_element.sub")
                self.dag_lines.append(f"VARS {node_name} seed=\"{seed}\"")
                self.dag_lines.append(f"RETRY {node_name} 3")
            self.dag_lines.append("")
            
            self._create_matrix_element_individual_sub(me_config)
        
        # Add harvest job
        if me_config.get('harvest', {}).get('enabled', True):
            self.dag_lines.append("JOB harvest_lhe harvest_lhe.sub")
            self.dag_lines.append("PARENT matrix_element CHILD harvest_lhe")
            self.dag_lines.append("")
            self._create_harvest_sub(me_config)
    
    def _create_matrix_element_sub(self, me_config: dict, start_seed: int, end_seed: int):
        """Create submission file for single-job matrix element generation."""
        condor_cfg = self.config.get('submission', {}).get('condor', {})
        
        self.sub_files['matrix_element.sub'] = f"""# Matrix Element Generation - Single Job Mode
# Processes all seeds in one job (efficient for HTCondor)

Universe = vanilla
Executable = scripts/run_matrix_element_batch.sh
Arguments = {start_seed} {end_seed}

Output = log/matrix_element_$(Cluster).stdout
Error = log/matrix_element_$(Cluster).stderr
Log = log/matrix_element_$(Cluster).log

Should_Transfer_Files = YES
Transfer_Input_Files = condor_submit.tar, scripts/run_matrix_element_batch.sh
WhenToTransferOutput = ON_EXIT

request_memory = {condor_cfg.get('request_memory', '15GB')}
request_cpus = {condor_cfg.get('request_cpus', 8)}
request_disk = {condor_cfg.get('request_disk', '10G')}

+JobFlavour = "{condor_cfg.get('job_flavour', 'tomorrow')}"

Queue 1
"""
    
    def _create_matrix_element_individual_sub(self, me_config: dict):
        """Create submission file for individual seed jobs."""
        condor_cfg = self.config.get('submission', {}).get('condor', {})
        
        self.sub_files['matrix_element.sub'] = f"""# Matrix Element Generation - Individual Jobs
# Uses the main.sh wrapper which calls helac_build_run.sh
Universe = vanilla
Executable = main.sh
Arguments = $(seed)

Output = log/matrix_element_$(Cluster)_$(Process).stdout
Error = log/matrix_element_$(Cluster)_$(Process).stderr
Log = log/matrix_element_$(Cluster)_$(Process).log

Should_Transfer_Files = YES
Transfer_Input_Files = condor_submit.tar, main.sh
WhenToTransferOutput = ON_EXIT

request_memory = {condor_cfg.get('request_memory', '15GB')}
request_cpus = {condor_cfg.get('request_cpus', 8)}
request_disk = {condor_cfg.get('request_disk', '8G')}

+JobFlavour = "{condor_cfg.get('job_flavour', 'tomorrow')}"

Queue
"""
    
    def _create_harvest_sub(self, me_config: dict):
        """Create submission file for LHE harvesting."""
        harvest_cfg = me_config.get('harvest', {})
        destination = harvest_cfg.get('destination', '/eos/user/c/chiw/MC_samples/LHE')
        
        self.sub_files['harvest_lhe.sub'] = f"""# LHE File Harvesting
Universe = vanilla
Executable = scripts/harvest_lhe.sh
Arguments = {destination}

Output = log/harvest_$(Cluster).stdout
Error = log/harvest_$(Cluster).stderr
Log = log/harvest_$(Cluster).log

request_memory = 2GB
request_cpus = 1
request_disk = 1G

+JobFlavour = "espresso"

Queue 1
"""
    
    def _generate_preprocessing_nodes(self):
        """Generate LHE preprocessing nodes."""
        preproc_cfg = self.config.get('lhe_preprocessing', {})
        
        if not preproc_cfg.get('enabled', False):
            return
            
        self.dag_lines.append("# LHE Preprocessing")
        
        # Two-tier split and shuffle
        if preproc_cfg.get('split', {}).get('shuffle', False):
            self.dag_lines.append("JOB split_shuffle split_shuffle.sub")
            self.dag_lines.append("PARENT harvest_lhe CHILD split_shuffle")
            self._create_split_shuffle_sub(preproc_cfg)
        
        # Event mixing (C++ implementation - requirement 6)
        if preproc_cfg.get('mixing', {}).get('enabled', False):
            self.dag_lines.append("JOB event_mixing event_mixing.sub")
            if preproc_cfg.get('split', {}).get('shuffle', False):
                self.dag_lines.append("PARENT split_shuffle CHILD event_mixing")
            else:
                self.dag_lines.append("PARENT harvest_lhe CHILD event_mixing")
            self._create_mixing_sub(preproc_cfg)
        
        # Gluon merging
        if preproc_cfg.get('gluon_merging', {}).get('enabled', False):
            self.dag_lines.append("JOB gluon_merge gluon_merge.sub")
            self.dag_lines.append("PARENT event_mixing CHILD gluon_merge")
            self._create_gluon_merge_sub(preproc_cfg)
        
        self.dag_lines.append("")
    
    def _create_split_shuffle_sub(self, preproc_cfg: dict):
        """Create submission file for split and shuffle."""
        split_cfg = preproc_cfg.get('split', {})
        
        self.sub_files['split_shuffle.sub'] = f"""# LHE Split and Shuffle
Universe = vanilla
Executable = scripts/split_shuffle.sh
Arguments = {split_cfg.get('tier1_size', 10000)} {split_cfg.get('tier2_size', 1000)}

Output = log/split_shuffle_$(Cluster).stdout
Error = log/split_shuffle_$(Cluster).stderr
Log = log/split_shuffle_$(Cluster).log

request_memory = 4GB
request_cpus = 2
request_disk = 20G

+JobFlavour = "microcentury"

Queue 1
"""
    
    def _create_mixing_sub(self, preproc_cfg: dict):
        """Create submission file for event mixing."""
        mixing_cfg = preproc_cfg.get('mixing', {})
        
        self.sub_files['event_mixing.sub'] = f"""# Event Mixing (C++ Implementation)
Universe = vanilla
Executable = bin/lhe_mixer
Arguments = --config workflow/mixing_config.json

Output = log/mixing_$(Cluster).stdout
Error = log/mixing_$(Cluster).stderr
Log = log/mixing_$(Cluster).log

Transfer_Input_Files = bin/lhe_mixer, workflow/mixing_config.json

request_memory = 8GB
request_cpus = 4
request_disk = 50G

+JobFlavour = "longlunch"

Queue 1
"""
    
    def _create_gluon_merge_sub(self, preproc_cfg: dict):
        """Create submission file for gluon merging."""
        merge_cfg = preproc_cfg.get('gluon_merging', {})
        
        self.sub_files['gluon_merge.sub'] = f"""# Gluon Merging
Universe = vanilla
Executable = bin/gluon_merger
Arguments = --delta-r {merge_cfg.get('merge_distance', 0.4)}

Output = log/gluon_merge_$(Cluster).stdout
Error = log/gluon_merge_$(Cluster).stderr
Log = log/gluon_merge_$(Cluster).log

request_memory = 4GB
request_cpus = 2
request_disk = 20G

+JobFlavour = "microcentury"

Queue 1
"""
    
    def _generate_showering_nodes(self):
        """Generate showering nodes."""
        shower_cfg = self.config.get('showering', {})
        
        if not shower_cfg.get('enabled', False):
            return
            
        self.dag_lines.append("# Parton Showering")
        self.dag_lines.append("JOB showering showering.sub")
        
        # Determine parent node
        preproc_cfg = self.config.get('lhe_preprocessing', {})
        if preproc_cfg.get('gluon_merging', {}).get('enabled', False):
            parent = "gluon_merge"
        elif preproc_cfg.get('mixing', {}).get('enabled', False):
            parent = "event_mixing"
        elif preproc_cfg.get('split', {}).get('shuffle', False):
            parent = "split_shuffle"
        elif preproc_cfg.get('enabled', False):
            parent = "harvest_lhe"
        else:
            parent = "matrix_element"
        
        self.dag_lines.append(f"PARENT {parent} CHILD showering")
        self.dag_lines.append("")
        
        self._create_showering_sub(shower_cfg)
    
    def _create_showering_sub(self, shower_cfg: dict):
        """Create submission file for showering."""
        keep_hepmc = shower_cfg.get('color_octet', {}).get('keep_hepmc', False)
        
        self.sub_files['showering.sub'] = f"""# Pythia8 Showering
Universe = vanilla
Executable = scripts/run_pythia_shower.sh
Arguments = --keep-hepmc {"true" if keep_hepmc else "false"}

Output = log/showering_$(Cluster).stdout
Error = log/showering_$(Cluster).stderr
Log = log/showering_$(Cluster).log

request_memory = 4GB
request_cpus = 2
request_disk = 20G

+JobFlavour = "microcentury"

Queue 1
"""
    
    def _generate_simulation_nodes(self):
        """Generate CMS simulation nodes (requirement 4)."""
        sim_cfg = self.config.get('simulation', {})
        
        if not sim_cfg.get('enabled', False):
            return
            
        self.dag_lines.append("# CMS Simulation Pipeline")
        
        steps = ['gen', 'sim', 'digi', 'reco', 'skim', 'ntuple']
        previous_step = "showering"
        
        for step in steps:
            step_cfg = sim_cfg.get('steps', {}).get(step, {})
            if not step_cfg.get('enabled', True):
                continue
                
            node_name = f"cms_{step}"
            self.dag_lines.append(f"JOB {node_name} cms_{step}.sub")
            self.dag_lines.append(f"PARENT {previous_step} CHILD {node_name}")
            self.dag_lines.append(f"RETRY {node_name} 2")
            
            self._create_cms_step_sub(step, step_cfg, sim_cfg)
            previous_step = node_name
        
        self.dag_lines.append("")
    
    def _create_cms_step_sub(self, step: str, step_cfg: dict, sim_cfg: dict):
        """Create submission file for a CMS simulation step."""
        cmssw_version = sim_cfg.get('cmssw_version', 'CMSSW_14_0_0')
        config_file = step_cfg.get('config', f'configs/cmssw/{step.upper()}_cfg.py')
        keep_output = step_cfg.get('keep_output', False)
        
        memory = "4GB"
        if step in ['sim', 'digi', 'reco']:
            memory = "8GB"
        
        self.sub_files[f'cms_{step}.sub'] = f"""# CMS {step.upper()} Step
Universe = vanilla
Executable = scripts/run_cmssw_step.sh
Arguments = {step} {config_file} {cmssw_version} {"keep" if keep_output else "delete"}

Output = log/cms_{step}_$(Cluster).stdout
Error = log/cms_{step}_$(Cluster).stderr
Log = log/cms_{step}_$(Cluster).log

request_memory = {memory}
request_cpus = 4
request_disk = 20G

+JobFlavour = "workday"

Queue 1
"""
    
    def _generate_cleanup_nodes(self):
        """Generate cleanup nodes for intermediate files."""
        sim_cfg = self.config.get('simulation', {})
        preserve = sim_cfg.get('preserve', ['*.lhe', '*.hepmc', '*MiniAOD*.root'])
        
        self.dag_lines.append("# Cleanup Intermediate Files")
        self.dag_lines.append("JOB cleanup cleanup.sub")
        
        # Find last step
        steps = ['cms_ntuple', 'cms_skim', 'cms_reco', 'cms_digi', 'cms_sim', 'cms_gen', 'showering']
        for step in steps:
            if f"JOB {step}" in "\n".join(self.dag_lines):
                self.dag_lines.append(f"PARENT {step} CHILD cleanup")
                break
        
        self.dag_lines.append("")
        
        self.sub_files['cleanup.sub'] = f"""# Cleanup Intermediate Files
Universe = vanilla
Executable = scripts/cleanup_intermediate.sh
Arguments = {' '.join(preserve)}

Output = log/cleanup_$(Cluster).stdout
Error = log/cleanup_$(Cluster).stderr
Log = log/cleanup_$(Cluster).log

request_memory = 1GB
request_cpus = 1
request_disk = 1G

+JobFlavour = "espresso"

Queue 1
"""
    
    def _write_submit_files(self):
        """Write all generated submission files."""
        for filename, content in self.sub_files.items():
            filepath = self.output_dir / filename
            with open(filepath, 'w') as f:
                f.write(content)
    
    def _write_dagman_config(self):
        """Write DAGman configuration file."""
        config_dir = self.output_dir / "config"
        config_dir.mkdir(parents=True, exist_ok=True)
        
        dagman_config = """# DAGman Configuration

# Maximum number of jobs running at once
DAGMAN_MAX_JOBS_SUBMITTED = 100

# Allow idle jobs
DAGMAN_MAX_JOBS_IDLE = 50

# Retry failed jobs
DAGMAN_RETRY_SUBMIT_FIRST = True
DAGMAN_RETRY_NODE_FIRST = True

# Log settings
DAGMAN_SUPPRESS_NOTIFICATION = True
"""
        
        with open(config_dir / "dagman.config", 'w') as f:
            f.write(dagman_config)


def main():
    parser = argparse.ArgumentParser(description="Generate DAGman workflow from YAML config")
    parser.add_argument("config", help="Path to workflow configuration YAML")
    parser.add_argument("--output", "-o", default="workflow",
                        help="Output directory for generated files")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.config):
        print(f"Error: Configuration file not found: {args.config}")
        sys.exit(1)
    
    generator = DAGmanGenerator(args.config, args.output)
    dag_path = generator.generate()
    
    print(f"Generated DAGman workflow: {dag_path}")
    print(f"Submit with: condor_submit_dag {dag_path}")


if __name__ == "__main__":
    main()
