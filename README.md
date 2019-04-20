# ODIN Spiking Neural Network (SNN) Processor

> *Copyright (C) 2016-2019, Université catholique de Louvain (UCLouvain), Belgium.*

> *Digital HDL source code of ODIN is free: you can redistribute it and/or modify it under the terms of the Solderpad Hardware License v2.0, which extends the Apache v2.0 license for hardware use.*

> *The software, hardware and materials distributed under this license are provided in the hope that it will be useful on an **'as is' basis, without warranties or conditions of any kind, either expressed or implied; without even the implied warranty of merchantability or fitness for a particular purpose**. See the Solderpad Hardware License for more details.*

> *You should have received a copy of the Solderpad Hardware License along with the ODIN HDL files (see [LICENSE](LICENSE) file). If not, see <https://solderpad.org/licenses/SHL-2.0/>.*


ODIN is an **o**nline-learning **di**gital spiking **n**euromorphic processor designed and prototyped in 28-nm FDSOI CMOS at Université catholique de Louvain (UCLouvain), published in 2019 in the *IEEE Transactions on Biomedical Circuits and Systems* journal. ODIN is based on a single 256-neuron 64k-synapse crossbar neurosynaptic core with the following key features:

* synapses embed spike-dependent synaptic plasticity (SDSP)-based online learning,
* neurons can phenomenologically reproduce the 20 Izhikevich behaviors.

ODIN is thus a versatile experimentation platform for learning at the edge, while demonstrating (i) record neuron and synapse densities compared to all previously-proposed spiking neural networks (SNNs) and (ii) the lowest energy per synaptic operation across previously-proposed digital SNNs.

In case you decide to use the ODIN HDL source code for academic or commercial use, we would appreciate if you let us know; **feedback is welcome**. Upon usage of the source code, please cite the associated paper (also available [here](https://arxiv.org/pdf/1804.07858.pdf)):

> C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning Digital Spiking Neuromorphic Processor in 28-nm CMOS," *IEEE Transactions on Biomedical Circuits and Systems*, vol. 13, no. 1, pp. 145-158, 2019.



## Documentation

> *The documentation for ODIN is under a Creative Commons Attribution 4.0 International License (see [doc/LICENSE](doc/LICENSE) file or http://creativecommons.org/licenses/by/4.0/).*

Documentation on the contents, usage and features of the ODIN HDL source code can be found in the [doc folder](doc/).

