SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training

# SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training

 Tianzhe Chu    Yuexiang Zhai    Jihan Yang    Shengbang Tong    Saining Xie    Dale Schuurmans    Quoc V. Le    Sergey Levine    Yi Ma 

# SFT Memorizes, RL Generalizes:  
A Comparative Study of Foundation Model Post-training

 Tianzhe Chu    Yuexiang Zhai    Jihan Yang    Shengbang Tong    Saining Xie    Dale Schuurmans    Quoc V. Le    Sergey Levine    Yi Ma 

###### Abstract

Supervised fine-tuning (SFT) and reinforcement learning (RL) are widely used post-training techniques for foundation models. However, their respective role in enhancing model generalization in rule-based reasoning tasks remains unclear. This paper studies the comparative effect of SFT and RL on generalization and memorization, focusing on text-based and visual reasoning tasks. We introduce GeneralPoints, an arithmetic reasoning card game, and also consider V-IRL, a real-world navigation environment, to assess how models trained with SFT and RL generalize to unseen variants in both novel textual rules and visual domains. We show that RL, especially when trained with an outcome-based reward, generalizes in both the rule-based textual and visual environments. SFT, in contrast, tends to memorize the training data and struggles to generalize out-of-distribution in either scenario. Further analysis reveals that RL improves the model’s underlying visual recognition capabilities, contributing to its enhanced generalization in visual domains. Despite RL’s superior generalization, we show that SFT is still helpful for effective RL training: SFT stabilizes the model’s output format, enabling subsequent RL to achieve its performance gains. These findings demonstrate the advantage of RL for acquiring generalizable knowledge in complex, multi-modal tasks.

Machine Learning, ICML 

  
 

## 1 Introduction

Although SFT and RL are both widely used for foundation model training (OpenAI, [2023b](https://arxiv.org/html/2501.17161v2#bib.bib31 ""); Google, [2023](https://arxiv.org/html/2501.17161v2#bib.bib19 ""); Jaech et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib23 ""); DeepSeekAI et al., [2025](https://arxiv.org/html/2501.17161v2#bib.bib16 "")), their distinct effects on generalization (Bousquet & Elisseeff, [2000](https://arxiv.org/html/2501.17161v2#bib.bib8 ""); Zhang et al., [2021](https://arxiv.org/html/2501.17161v2#bib.bib62 "")) remain unclear, making it challenging to build reliable and robust AI systems. A key challenge in analyzing the generalizability of foundation models (Bommasani et al., [2021](https://arxiv.org/html/2501.17161v2#bib.bib7 ""); Brown et al., [2020](https://arxiv.org/html/2501.17161v2#bib.bib9 "")) is to separate data memorization111We use “memorization” the refer a model’s capacity to generate near-exact copies of training examples when prompted based on information present in the training dataset. This definition explicitly excludes bitwise or codewise replication of training data within the model itself. from the acquisition of transferable principles. Thus, we investigate the key question whether SFT or RL primarily memorize training data (Allen-Zhu & Li, [2023a](https://arxiv.org/html/2501.17161v2#bib.bib4 ""); Ye et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib56 ""); Kang et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib25 "")), or whether they learn generalizable rules that can adapt to novel task variants.

To address this question, we focus on two aspects of generalization: textual rule-based generalization and visual generalization. For textual rules, we study the ability of a model to apply learned rules (given text instructions) to variants of these rules (Zhu et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib68 ""); Yao et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib55 ""); Ye et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib56 "")). For vision-language models (VLMs), visual generalization measures the consistency of performance with variations in visual input, such as color and spatial layout, within a given task. For studying text-based and visual generalization, we investigate two different tasks that embody rule-based and visual variants. Our first task is GeneralPoints, an original card game task similar to Points24 of RL4VLM (Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")), which is designed to evaluate a model’s arithmetic reasoning capabilities. The model receives four cards (presented as a text description or an image), and is required to compute a target number (24 by default) using each card’s numerical value exactly once. Second, we adopt V-IRL (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")), a real-world navigation task that focuses on the model’s spatial reasoning capabilities.

![Refer to caption](x1.png)

Figure 1: A comparative study of RL and SFT on the visual navigation environment V-IRL (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")) for OOD generalization. OOD curves represent performance on the same task, using a different textual action space. See detailed descriptions of the task in Section [5.1](https://arxiv.org/html/2501.17161v2#S5.SS1 "5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

We adopt a multi-step RL framework similar to Zhai et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")), by instantiating RL after running SFT on the backbone model (Dubey et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib17 "")), using the sequential revision formulation (Snell et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib40 "")). In both GeneralPoints and V-IRL, we observe that RL learns generalizable rules (expressed in text), where in-distribution performance gains also transfer to unseen rules. In contrast, SFT appears to memorize the training rules and does not generalize (see [Figure 1](https://arxiv.org/html/2501.17161v2#S1.F1 "In 1 Introduction ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") for an example). Beyond textual rule-based generalization, we further investigate generalization in the visual domain and observe that RL also generalizes to visual OOD tasks, whereas SFT continues to struggle. As a by-product of the visual OOD generalization capability, our multi-turn RL approach achieves state-of-the-art performance on the V-IRL mini benchmark, by +33.8% (44.0%→→\\rightarrow→77.8%) (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")), highlighting the generalization capability of RL. To understand how RL affects the visual abilities of a model, we conducted additional analysis on GeneralPoints, revealing that training RL with an outcome-based reward function (Cobbe et al., [2021](https://arxiv.org/html/2501.17161v2#bib.bib15 "")) improves visual recognition capabilities. Although RL exhibits superior generalization compared to SFT, we show that SFT is still necessary to stabilize the model’s output format, enabling RL to achieve its performance gains. Last but not least, we observe that scaling up the inference time compute by increasing the number of maximal steps leads to better generalization.

## 2 Related Works

#### Post-training.

Post-training is crucial for enhancing model performance (Zhang et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib64 ""); Hoffmann et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib21 ""); OpenAI, [2023b](https://arxiv.org/html/2501.17161v2#bib.bib31 ""); Google, [2023](https://arxiv.org/html/2501.17161v2#bib.bib19 ""); Touvron et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib48 "")). This stage commonly utilizes large-scale supervised fine-tuning (SFT) (Radford et al., [2018](https://arxiv.org/html/2501.17161v2#bib.bib34 ""); Brown et al., [2020](https://arxiv.org/html/2501.17161v2#bib.bib9 ""); Radford et al., [2021](https://arxiv.org/html/2501.17161v2#bib.bib35 ""); Wei et al., [2022a](https://arxiv.org/html/2501.17161v2#bib.bib50 ""); Chung et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib14 ""); Zhou et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib66 "")) and/or reinforcement learning (RL) (Ziegler et al., [2019](https://arxiv.org/html/2501.17161v2#bib.bib69 ""); Ouyang et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib32 ""); Sun et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib41 ""); Abdulhai et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib1 ""); Zhou et al., [2024b](https://arxiv.org/html/2501.17161v2#bib.bib67 ""); Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")). SFT adapts pre-trained models to downstream tasks by training them on task-specific, often instruction-formatted datasets. Previous work, such as FLAN (Wei et al., [2022a](https://arxiv.org/html/2501.17161v2#bib.bib50 "")), demonstrates that fine-tuning on diverse instruction-tuning datasets significantly enhances zero-shot performance on unseen tasks. Furthermore, LIMA (Zhou et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib66 "")) shows that supervised fine-tuning acts as a “format teacher” effectively adapting the model’s responses to a desired format while leveraging the capabilities of pre-trained LLMs. In contrast, RL (Ziegler et al., [2019](https://arxiv.org/html/2501.17161v2#bib.bib69 ""); Ouyang et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib32 ""); Sun et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib41 ""); Ramamurthy et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib37 ""); Abdulhai et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib1 ""); Zhou et al., [2024b](https://arxiv.org/html/2501.17161v2#bib.bib67 ""); Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")) has been primarily used to align models with human preferences or training the foundational model to solve a specific task (Abdulhai et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib1 ""); Zhou et al., [2024b](https://arxiv.org/html/2501.17161v2#bib.bib67 ""); Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 ""); Chen et al., [2024b](https://arxiv.org/html/2501.17161v2#bib.bib12 "")). Our work differs from prior studies, as we aim to comparatively analyze the generalization and memorization of SFT and RL on both LLM and VLM, while previous studies have focused primarily on only one of these two post-training methods (or only study LLM or VLM) or on only one post-training method.

#### Memorization and generalization in LLM/VLM.

Several studies have examined the interplay between memorization and generalization in neural networks (Han et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib20 ""); Carlini et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib10 ""); Yang et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib54 "")). In LLMs, memorization can manifest as the model memorizing the training data (Carlini et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib10 ""); Jiang et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib24 ""); Kang et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib25 "")), while generalization reflects the divergence between the model’s output distribution and the pre-training data distribution (Zhang et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib63 "")). Prior studies suggest that LLMs exhibit more overfitting on simpler, knowledge-intensive tasks and greater generalization on more complex, reasoning-intensive ones (Wang et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib49 ""); Qi et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib33 "")). For example, recent studies (Ye et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib56 ""); Allen-Zhu, [2024](https://arxiv.org/html/2501.17161v2#bib.bib3 ""); Allen-Zhu & Li, [2023a](https://arxiv.org/html/2501.17161v2#bib.bib4 ""), [b](https://arxiv.org/html/2501.17161v2#bib.bib5 ""), [2024](https://arxiv.org/html/2501.17161v2#bib.bib6 ""); Tong et al., [2024b](https://arxiv.org/html/2501.17161v2#bib.bib45 "")) have demonstrated that LLMs develop reasoning skill sets beyond their training data by pre-computing reasoning graphs before autoregressive generation, which provides compelling evidence of generalization. Our study takes a different approach by investigating the role of different post-training paradigms on memorization versus generalization in the context of textual ruled-based and visual variants. We conduct comparative studies in both unimodal (LLM) and multimodal (VLM) settings, and demonstrate that RL leads to better generalization performance than SFT.

#### Scaling up inference-time compute.

Recent research has increasingly focused on scaling up inference-time computation to improve model performance (Wei et al., [2022b](https://arxiv.org/html/2501.17161v2#bib.bib51 ""); Yao et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib55 ""); Snell et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib40 ""); Jaech et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib23 "")). Early studies (Wei et al., [2022b](https://arxiv.org/html/2501.17161v2#bib.bib51 ""); Yao et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib55 "")) prompted models to generate intermediate reasoning steps and extend the responses before producing a final answer. Subsequent work (Zelikman et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib59 ""); Feng et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib18 ""); Tian et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib43 ""); Chen et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib11 ""); Snell et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib40 "")) has demonstrated that fine-tuning verifiers during inference improves model accuracy, effectively utilizing test-time computation. Notably, recent findings (Jaech et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib23 ""); DeepSeekAI et al., [2025](https://arxiv.org/html/2501.17161v2#bib.bib16 "")) reveal “scaling laws” for inference-time compute, highlighting significant performance gains with increased computational resources. Our work builds upon these findings in two ways. First, we integrate insights from inference-time verification into a multi-turn RL formulation that allows the model to identify and correct its errors. Second, we examine the impact of inference-time verification on RL generalization, demonstrating that scaling up inference-time verification (in terms of the maximum number of verification steps) is a key for RL to generalize.

#### Improving visual capability in VLMs.

While VLMs have demonstrated remarkable skill across a wide range of challenging tasks, such as solving advanced college exam questions (Lu et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib29 ""); Yue et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib57 ""), [b](https://arxiv.org/html/2501.17161v2#bib.bib58 "")) and spatial understanding tasks (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 ""), [b](https://arxiv.org/html/2501.17161v2#bib.bib53 "")), they also exhibit limitations in visual perception (Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 ""), [b](https://arxiv.org/html/2501.17161v2#bib.bib61 ""); Tong et al., [2024c](https://arxiv.org/html/2501.17161v2#bib.bib46 ""), [d](https://arxiv.org/html/2501.17161v2#bib.bib47 ""); Rahmanzadehgervi et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib36 "")). Prior efforts to enhance VLMs’ visual perception include combining multiple visual encoders (Tong et al., [2024d](https://arxiv.org/html/2501.17161v2#bib.bib47 ""); Kar et al., [2025](https://arxiv.org/html/2501.17161v2#bib.bib26 ""); Tong et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib44 "")), curating high-quality SFT data (Chen et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib13 ""); Liu et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib28 ""); Tong et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib44 "")), and improving the SFT training recipe by unfreezing the visual backbone (Liu et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib27 ""); Tong et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib44 "")). While these prior works primarily focus on experiments during the SFT stage, our work demonstrates that RL can also improve visual perception.

## 3 Preliminaries

#### Standard RL terminology.

We consider finite horizon decision making, and adopt standard notation from the classical RL literature (Sutton & Barto, [2018](https://arxiv.org/html/2501.17161v2#bib.bib42 ""); Agarwal et al., [2019](https://arxiv.org/html/2501.17161v2#bib.bib2 "")), where 𝒮𝒮\\mathcal{S}caligraphic\_S denotes the state space, 𝒜𝒜\\mathcal{A}caligraphic\_A denotes the action space, r:𝒮×𝒜→ℝ:𝑟→𝒮𝒜ℝr:\\mathcal{S}\\times\\mathcal{A}\\rightarrow\\mathbb{R}italic\_r : caligraphic\_S × caligraphic\_A → blackboard\_R denotes the reward function, and T𝑇Titalic\_T denotes the maximum number of steps per episode. The goal is to learn a policy π:𝒮→𝒜:𝜋→𝒮𝒜{\\pi:\\mathcal{S}\\rightarrow\\mathcal{A}}italic\_π : caligraphic\_S → caligraphic\_A that maximizes the overall return maxπ∈Π⁡𝔼π⁢\[∑t\=0Trt\]subscript𝜋Πsubscript𝔼𝜋delimited-\[\]superscriptsubscript𝑡0𝑇subscript𝑟𝑡{\\max\_{\\pi\\in\\Pi}\\mathbb{E}\_{\\pi}\\left\[\\sum\_{t=0}^{T}r\_{t}\\right\]}roman\_max start\_POSTSUBSCRIPT italic\_π ∈ roman\_Π end\_POSTSUBSCRIPT blackboard\_E start\_POSTSUBSCRIPT italic\_π end\_POSTSUBSCRIPT \[ ∑ start\_POSTSUBSCRIPT italic\_t = 0 end\_POSTSUBSCRIPT start\_POSTSUPERSCRIPT italic\_T end\_POSTSUPERSCRIPT italic\_r start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT \], where rtsubscript𝑟𝑡r\_{t}italic\_r start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT denotes r⁢(st,at)𝑟subscript𝑠𝑡subscript𝑎𝑡r(s\_{t},a\_{t})italic\_r ( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , italic\_a start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ). Without loss of generality, we use π⁢(a|s)∈\[0,1\]𝜋conditional𝑎𝑠01\\pi(a|s)\\in\[0,1\]italic\_π ( italic\_a | italic\_s ) ∈ \[ 0 , 1 \] to denote probability of π𝜋\\piitalic\_π choosing a𝑎aitalic\_a at s𝑠sitalic\_s.

#### Adapting RL terminology to LLM/VLM with a verifier.

We adopt a multi-turn RL setting for foundation model training (Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")). Let 𝒱𝒱\\mathcal{V}caligraphic\_V represent the discrete and finite vocabulary (token) space. The input and output text spaces are denoted by 𝒱msuperscript𝒱𝑚\\mathcal{V}^{m}caligraphic\_V start\_POSTSUPERSCRIPT italic\_m end\_POSTSUPERSCRIPT and 𝒱nsuperscript𝒱𝑛\\mathcal{V}^{n}caligraphic\_V start\_POSTSUPERSCRIPT italic\_n end\_POSTSUPERSCRIPT respectively, where m𝑚mitalic\_m and n𝑛nitalic\_n are the maximum token length of the input sequence 𝐯insuperscript𝐯in\\mathbf{v}^{\\text{in}}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT and output sequence 𝐯outsuperscript𝐯out\\mathbf{v}^{\\text{out}}bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT. For models requiring visual inputs (VLM), we define 𝒪𝒪\\mathcal{O}caligraphic\_O as the space of all RGB images. The state space, denoted by 𝒮𝒮\\mathcal{S}caligraphic\_S, is defined as 𝒮:=𝒱m×𝒪assign𝒮superscript𝒱𝑚𝒪\\mathcal{S}:=\\mathcal{V}^{m}\\times\\mathcal{O}caligraphic\_S := caligraphic\_V start\_POSTSUPERSCRIPT italic\_m end\_POSTSUPERSCRIPT × caligraphic\_O for VLM, and 𝒮:=𝒱massign𝒮superscript𝒱𝑚\\mathcal{S}:=\\mathcal{V}^{m}caligraphic\_S := caligraphic\_V start\_POSTSUPERSCRIPT italic\_m end\_POSTSUPERSCRIPT for LLM. The action space 𝒜𝒜\\mathcal{A}caligraphic\_A is defined as 𝒜:=𝒱nassign𝒜superscript𝒱𝑛\\mathcal{A}:=\\mathcal{V}^{n}caligraphic\_A := caligraphic\_V start\_POSTSUPERSCRIPT italic\_n end\_POSTSUPERSCRIPT. We use 𝖵𝖤𝖱:𝒱n→ℝ×𝒱k:𝖵𝖤𝖱→superscript𝒱𝑛ℝsuperscript𝒱𝑘\\mathsf{VER}:\\mathcal{V}^{n}\\rightarrow\\mathbb{R}\\times\\mathcal{V}^{k}sansserif\_VER : caligraphic\_V start\_POSTSUPERSCRIPT italic\_n end\_POSTSUPERSCRIPT → blackboard\_R × caligraphic\_V start\_POSTSUPERSCRIPT italic\_k end\_POSTSUPERSCRIPT to denote a verifier, which evaluates the outcome of 𝐯outsuperscript𝐯out\\mathbf{v}^{\\text{out}}bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT and generates an outcome-based reward function (Cobbe et al., [2021](https://arxiv.org/html/2501.17161v2#bib.bib15 ""); Hosseini et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib22 ""); Snell et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib40 ""); Setlur et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib39 "")) r𝑟ritalic\_r along with textual information 𝐯versuperscript𝐯ver\\mathbf{v}^{\\text{ver}}bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT. Mathematically, at time t𝑡titalic\_t, 𝖵𝖤𝖱⁢(𝐯tout)↦(rt,𝐯tver)maps-to𝖵𝖤𝖱subscriptsuperscript𝐯out𝑡subscript𝑟𝑡subscriptsuperscript𝐯ver𝑡\\mathsf{VER}(\\mathbf{v}^{\\text{out}}\_{t})\\mapsto(r\_{t},\\mathbf{v}^{\\text{ver}}% \_{t})sansserif\_VER ( bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) ↦ ( italic\_r start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ). Similar to Zhai et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")), we treat the model with parameter θ𝜃\\thetaitalic\_θ as our policy network πθ:𝒮→𝒱n:subscript𝜋𝜃→𝒮superscript𝒱𝑛\\pi\_{\\theta}:\\mathcal{S}\\rightarrow\\mathcal{V}^{n}italic\_π start\_POSTSUBSCRIPT italic\_θ end\_POSTSUBSCRIPT : caligraphic\_S → caligraphic\_V start\_POSTSUPERSCRIPT italic\_n end\_POSTSUPERSCRIPT, and adopt PPO (Schulman et al., [2017](https://arxiv.org/html/2501.17161v2#bib.bib38 "")) as the backbone RL algorithm for updating πθsubscript𝜋𝜃\\pi\_{\\theta}italic\_π start\_POSTSUBSCRIPT italic\_θ end\_POSTSUBSCRIPT.

#### Sequential revision.

For modeling the state-action transition, we adopt the sequential revision formulation (Snell et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib40 "")). Specifically, at time step t\=0𝑡0t=0italic\_t = 0 the initial input 𝐯0insubscriptsuperscript𝐯in0\\mathbf{v}^{\\text{in}}\_{0}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT 0 end\_POSTSUBSCRIPT consists of the system prompt. For subsequent time steps (t≥1)𝑡1(t\\geq 1)( italic\_t ≥ 1 ), the input prompt 𝐯tinsubscriptsuperscript𝐯in𝑡\\mathbf{v}^{\\text{in}}\_{t}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT comprises the system prompt concatenated with all prior model and verifier outputs, denoted by \[𝐯kout,𝐯kver\]k\=0t−1superscriptsubscriptsubscriptsuperscript𝐯out𝑘subscriptsuperscript𝐯ver𝑘𝑘0𝑡1\[\\mathbf{v}^{\\text{out}}\_{k},\\mathbf{v}^{\\text{ver}}\_{k}\]\_{k=0}^{t-1}\[ bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_k end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_k end\_POSTSUBSCRIPT \] start\_POSTSUBSCRIPT italic\_k = 0 end\_POSTSUBSCRIPT start\_POSTSUPERSCRIPT italic\_t - 1 end\_POSTSUPERSCRIPT. An illustration of the sequential revision is provided in Figure [2](https://arxiv.org/html/2501.17161v2#S3.F2 "Figure 2 ‣ Sequential revision. ‣ 3 Preliminaries ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") (also see Figure 5 of Snell et al. ([2024](https://arxiv.org/html/2501.17161v2#bib.bib40 ""))), and an example of the state-action transition is shown in Figure [3](https://arxiv.org/html/2501.17161v2#S3.F3 "Figure 3 ‣ Sequential revision. ‣ 3 Preliminaries ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

Figure 2: An example of the sequential revision formulation with a verifier. The model generate the next answer 𝐯t+1outsubscriptsuperscript𝐯out𝑡1\\mathbf{v}^{\\text{out}}\_{t+1}bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t + 1 end\_POSTSUBSCRIPT conditioned on all previous answers and information (𝐯iout,𝐯tver,0≤i≤t)subscriptsuperscript𝐯out𝑖subscriptsuperscript𝐯ver𝑡0𝑖𝑡(\\mathbf{v}^{\\text{out}}\_{i},\\mathbf{v}^{\\text{ver}}\_{t},0\\leq i\\leq t)( bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_i end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , 0 ≤ italic\_i ≤ italic\_t ) from the verifier.

Figure 3: An template of our prompt update for constructing 𝐯t+1insubscriptsuperscript𝐯in𝑡1\\mathbf{v}^{\\text{in}}\_{t+1}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t + 1 end\_POSTSUBSCRIPT. The brown parts marks the task and related information, and the purple parts denote the state (st)subscript𝑠𝑡(s\_{t})( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) specific info. The blue and red describe the output from the model and verifier, respectively. 

## 4 Evaluation Tasks

To evaluate the generalization of different post-training methods, we select two tasks that each offer rule and visual variations. The first task, GeneralPoints, is a new environment we have designed that allows assessment of arithmetic reasoning abilities (Section [4.1](https://arxiv.org/html/2501.17161v2#S4.SS1 "4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). The second task, V-IRL (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")), is chosen to examine the model’s reasoning capabilities in an open-world visual navigation domain (Section [4.2](https://arxiv.org/html/2501.17161v2#S4.SS2 "4.2 The V-IRL Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

### 4.1 The General Points Environment

Our original GeneralPoints environment, instantiated on top of the Points24 environment (Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")), is designed to evaluate generalization of arithmetic reasoning. Each state s𝑠sitalic\_s of the environment contains 4 cards, described as text (in the GP-L variant) or presented as an image (in the GP-VL variant); see [Figure 2](https://arxiv.org/html/2501.17161v2#S3.F2 "In Sequential revision. ‣ 3 Preliminaries ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") left for a visual example of GeneralPoints. The goal is to produce an equation that equals a target number (24 by default) using all 4 numbers from the cards exactly once. Detailed examples of the state-action transitions are provided in Appendix [A.2](https://arxiv.org/html/2501.17161v2#A1.SS2 "A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). Note that when input from GeneralPoints is presented in an image (GP-VL), it naturally introduces additional visual challenges requiring the VLM to recognize all cards before solving the equation.

#### Rule variations.

To study whether the model learns arithmetic operations or simply memorizes the post-training data, we introduce rule variations in GeneralPoints. These variations consist of interpreting the symbols 'J', 'Q', and 'K' either as '11', '12', and '13', respectively, or all as the same number '10'. These variations ensure a rigorous evaluation of the model’s ability to generalize arithmetic reasoning across diverse settings. Each rule is specified as text in the input prompt, see the {tasks rules} part in [Figure 3](https://arxiv.org/html/2501.17161v2#S3.F3 "In Sequential revision. ‣ 3 Preliminaries ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). For studying ruled based generalization, we post-train the model using one rule, then evaluate using a different rule.

#### Visual variations.

The GeneralPoints environment can also be naturally customized to evaluate generalization across visual variants. Since the major visual challenge is to recognize the number of each card, agnostic to the the color of the cards, we consider the cards with different colors as visual variants of the task. In the visual generalization setting, we train the model using cards of one color, then test OOD performance using the other color.

Figure 4: Demonstration of one navigation task in V-IRL. Agent navigates from place to place following the given linguistic navigation instructions in V-IRL. The navigation procedure is shown at the top, with the navigation instructions displayed below. Visual observation-related information is highlighted in green, while action-related information is marked in orange.

### 4.2 The V-IRL Environment

While the GeneralPoints environment is designed to assess arithmetic reasoning abilities, we further utilize the V-IRL environment (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")) to study spatial reasoning ability in an open-world navigation domain that uses realistic visual input. As in GeneralPoints we consider two versions of the environment, one (V-IRL-L) that consists of pure language descriptions,222The visual input can be parsed into pure text description, see more details in Yang et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")) and an illustration of pure text the version in [Figure 14](https://arxiv.org/html/2501.17161v2#A2.F14 "In B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). and another (V-IRL-VL) that includes vision-language input. The major visual challenge in V-IRL involves recognizing different landmarks from the visual observation333See Figure [4](https://arxiv.org/html/2501.17161v2#S4.F4 "Figure 4 ‣ Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), the model needs to recognize landmarks like The Dutch, Lola Taverna, and Shuka from the visual observation, and relate these landmarks with the textual instructions for taking the right action. before taking an action. The goal is to navigate to a target location by following a set of instructions that contain spatial information. A detailed example of one environment step is shown in Appendix [B.2](https://arxiv.org/html/2501.17161v2#A2.SS2 "B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

#### Rule variations.

To evaluate whether the model possesses spatial knowledge or simply memorizes post-training data, we consider two distinct action space configurations. The first variant utilizes an absolute orientation action space, which includes {'north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'}. The second variant employs a relative orientation action space, containing {'left', 'right', 'slightly left', 'slightly right'}. This relative configuration adjusts the current orientation by 90 degrees or 45 degrees to the left or right, respectively. An overview of a navigation task in V-IRL is provided in Figure [4](https://arxiv.org/html/2501.17161v2#S4.F4 "Figure 4 ‣ Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), and a detailed state-action transition in V-IRL is provided in [Figure 13](https://arxiv.org/html/2501.17161v2#A2.F13 "In B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") (in [Section B.2](https://arxiv.org/html/2501.17161v2#A2.SS2 "B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

#### Visual variations.

The key visual challenge in V-IRL is to recognize landmarks from the visual observations (e.g., the green parts in [Figure 4](https://arxiv.org/html/2501.17161v2#S4.F4 "In Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). Since the V-IRL environment contains visual observations from different cities, we can assess visual generalization in V-IRL by training the model to navigate in one location and then evaluate its performance in different locations.

## 5 Results

![Refer to caption](x4.png)

Figure 5: Success rate (%) - GFLOPs trendlines for RL and SFT on GeneralPoints and V-IRL. The top row shows in-distribution performance, while the bottom row shows out-of-distribution performance. Results are presented for both pure language (-L) and vision-language (-VL) variants of each task. For GeneralPoints, we report the episode success rate, while for V-IRL, we report per-step accuracy with overall success rate in [Figures 1](https://arxiv.org/html/2501.17161v2#S1.F1 "In 1 Introduction ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [19](https://arxiv.org/html/2501.17161v2#A4.F19 "Figure 19 ‣ D.2 More results on V-IRL-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). Detailed evaluation setups (and curve smoothing) are provided in [Section C.3](https://arxiv.org/html/2501.17161v2#A3.SS3 "C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

![Refer to caption](x5.png)

Figure 6: Comparison of out-of-distribution performance under rule variants. We report the success rate for GeneralPoints and per-step-accuracy for V-IRL. For each subplot, RL and SFT are trained with equal computation, and their shared initial checkpoint (marked as Init) is set as baseline. Detailed setups are provided in [Section C.3](https://arxiv.org/html/2501.17161v2#A3.SS3 "C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

In this section, we present experiments that investigate the generalization abilities induced by post-training with RL and SFT. We adopt Llama-3.2-Vision-11B (Dubey et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib17 "")) as the backbone model. Following the standard pipelines of RLHF (Ouyang et al., [2022](https://arxiv.org/html/2501.17161v2#bib.bib32 "")) and RL4VLM (Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")), we initialize the model with SFT before running RL. We specifically study the following questions. [Section 5.1](https://arxiv.org/html/2501.17161v2#S5.SS1 "5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"): how does SFT or RL affect the model’s generalization to different rules? [Section 5.2](https://arxiv.org/html/2501.17161v2#S5.SS2 "5.2 Generalization in Visual Out-of-Distribution Tasks ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"): when the model contains a visual component, how does RL/SFT affect its generalization to different visual variants? [Section 5.3](https://arxiv.org/html/2501.17161v2#S5.SS3 "5.3 RL Improves Visual Capabilities ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"): how does RL/SFT affect visual recognition capability in a VLM? [Section 5.4](https://arxiv.org/html/2501.17161v2#S5.SS4 "5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"): what role does SFT play in RL training? [Section 5.5](https://arxiv.org/html/2501.17161v2#S5.SS5 "5.5 Role of Verification Iterations ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"): how does the number of verification iterations affect generalization?

### 5.1 Generalization across Rules

We evaluate the performance of different post-training methods on GeneralPoints and V-IRL, each of which has a pure language (-L) and a vision-language (-VL) variant, and each encompassing rule variations. For each task, we separately scale the training compute for RL and SFT on a single rule. We consider the results on the trained rule as in-distribution (ID) performance, whereas results on the unseen rules measures out-of-distribution (OOD) generalization. In GeneralPoints, the ID case treats all 'J', 'Q', 'K' as 10, and the OOD cases interprets them as 11, 12, and 13. As for V-IRL, the ID case adopts the absolute orientation coordinate system and the OOD case uses the relative orientation action space. Other details and additional experimental setup can be found in [Appendix C](https://arxiv.org/html/2501.17161v2#A3 "Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

#### RL generalizes, SFT memorizes.

As illustrated in [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), RL consistently improves OOD performance on all tasks, including both unimodal (LLM) and multimodal (VLM). Specifically, [Figure 6](https://arxiv.org/html/2501.17161v2#S5.F6 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") demonstrates that RL achieves an increase of +3.5% on GP-L (11.5% →→\\rightarrow→ 15.0%) and +11.0% on V-IRL-L (80.8% →→\\rightarrow→ 91.8%). Even with the additional challenge of visual recognition in the VLM, RL maintains consistent performance improvements of +3.0% (11.2% →→\\rightarrow→ 14.2%) on GP-VL and +9.3% (35.7% →→\\rightarrow→ 45.0%) on V-IRL-VL, respectively. In contrast, SFT consistently exhibits performance degradation across all OOD evaluations on all tasks: -8.1% on GP-L (11.5% →→\\rightarrow→ 3.4%), -79.5% on V-IRL-L (80.8% →→\\rightarrow→ 1.3%), -5.6% (11.2% →→\\rightarrow→ 5.6%) on GP-VL, and -33.2% (35.7% →→\\rightarrow→ 2.5%) on V-IRL-VL.

![Refer to caption](x6.png)

Figure 7: Comparison of out-of-distribution performance under visual variants. Similar to [Figures 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [6](https://arxiv.org/html/2501.17161v2#S5.F6 "Figure 6 ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we present both the performance dynamics (shown as lines) and final performance (shown as bars) for visual out-of-distribution evaluations. The previous state-of-the-art on V-IRL VLN mini benchmark (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")) is marked in orange. Detailed evaluation setups (and curve smoothing) are provided in [Section C.3](https://arxiv.org/html/2501.17161v2#A3.SS3 "C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). 

![Refer to caption](x7.png)

Figure 8: Recognition vs. success rate for RL and SFT under different variants in GP-VL. We report both in-distribution ( red) and OOD ( blue) performance of recognition (y-axis) and episode success rate (x-axis). We denote the training compute of each data point via transparency (color bar) while connected (⋆⋆\\star⋆-∘\\circ∘) pairs are evaluated using same checkpoints. As scaling up post-training compute, RL improves both recognition and overall accuracy, while SFT shows opposite effect.

### 5.2 Generalization in Visual Out-of-Distribution Tasks

Section [5.1](https://arxiv.org/html/2501.17161v2#S5.SS1 "5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") demonstrates that RL yields generalization across rule variations, whereas SFT exhibits the opposite trend. Since VLMs also incorporate a visual modality, we next study the effects of visual variation in OOD generalization. For GeneralPoints, we train the VLM using the black suits (♠, ♣) and test out-of-distribution performance on the red suits (♥, ♠). For V-IRL, we train the model on routes collected in New York City and evaluate it on the original V-IRL VLN mini benchmark (Yang et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")) containing routes from various cities worldwide (see [Section B.1](https://arxiv.org/html/2501.17161v2#A2.SS1 "B.1 Data ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") for details). Note that the rules remain consistent across experiments in this section.

#### RL generalizes in visual OOD tasks.

As shown in [Figure 7](https://arxiv.org/html/2501.17161v2#S5.F7 "In RL generalizes, SFT memorizes. ‣ 5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we observe that RL still generalizes in visual OOD tasks, while SFT continues to suffer. Specifically, in GP-VL and VIRL-VL, RL achieves performance improvements of +17.6% (23.6% →→\\rightarrow→ 41.2%), +61.1% (16.7% →→\\rightarrow→ 77.8%), whereas SFT suffers from performance decreases of -9.9% (23.6% →→\\rightarrow→ 13.7%) and -5.6% (16.7% →→\\rightarrow→ 11.1%). As a byproduct of this visual OOD study, we also show that our multi-turn RL formulation improves the state-of-the-art results (see Table 5 of Yang et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 ""))) on the V-IRL mini benchmark by +33.8% (44.0% →→\\rightarrow→ 77.8%). Notably, unlike the previous state-of-the-art approach reported in V-IRL, which relies on a two stage VLM-LLM collaboration technique and tailored prompt engineering on closed-sourced model (OpenAI, [2023a](https://arxiv.org/html/2501.17161v2#bib.bib30 "")), our end-to-end RL approach enables an open-sourced model (Dubey et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib17 "")) to reach superior performance.

### 5.3 RL Improves Visual Capabilities

Building upon the above observation that VLMs trained with RL generalize to visual OOD tasks (Section [5.2](https://arxiv.org/html/2501.17161v2#S5.SS2 "5.2 Generalization in Visual Out-of-Distribution Tasks ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")), we consider a natural follow-up question: How does RL affect VLMs’ visual capabilities? To study this question, we conducted additional ablation studies in the GP-VL environment to investigate the OOD performance of RL and SFT, along with the model’s visual recognition accuracy, in terms of recognizing the 4 cards from the input image. In particular, we study how scaling post-training compute via RL/SFT both affects generalization in rule-based OOD ([Figure 8](https://arxiv.org/html/2501.17161v2#S5.F8 "In RL generalizes, SFT memorizes. ‣ 5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") left), and visual recognition accuracy and visual OOD ([Figure 8](https://arxiv.org/html/2501.17161v2#S5.F8 "In RL generalizes, SFT memorizes. ‣ 5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") right).

#### Scaling RL improves visual recognition accuracy in VLM training.

As shown in [Figure 8](https://arxiv.org/html/2501.17161v2#S5.F8 "In RL generalizes, SFT memorizes. ‣ 5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we observe that the VLM’s visual recognition accuracy largely affects the overall performance, which was similarly observed in Zhong et al. ([2024](https://arxiv.org/html/2501.17161v2#bib.bib65 "")). In addition, scaling up RL compute also improves visual recognition accuracy, as a byproduct of its generalization capability, while scaling SFT deteriorates both visual recognition accuracy and overall performance. Additional experimental results are provided in [Figures 16](https://arxiv.org/html/2501.17161v2#A3.F16 "In Computation estimation. ‣ C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [17](https://arxiv.org/html/2501.17161v2#A4.F17 "Figure 17 ‣ RL. ‣ D.1 Ablation Studies on GP-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") of Appendix [D.1](https://arxiv.org/html/2501.17161v2#A4.SS1 "D.1 Ablation Studies on GP-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

### 5.4 The Role of SFT for RL Training

Despite the superiority of RL in generalizing the model’s reasoning and visual capabilities, as discussed previously, the experimental pipeline still instantiates RL after SFT. In this subsection, we focus on another key question: Is SFT necessary for RL training? To answer this question, we conduct additional experiments that directly apply end-to-end RL to post-train the base model Llama3.2 using GeneralPoints in the purely language case ([Figure 9](https://arxiv.org/html/2501.17161v2#S5.F9 "In 5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

![Refer to caption](x8.png)

Figure 9: RL experiments on GP-L without SFT initialization. All trials fail due to poor instruction following capability of the base model. 

#### SFT is necessary for RL training when the backbone model does not follow instructions.

[Figure 9](https://arxiv.org/html/2501.17161v2#S5.F9 "In 5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") shows that without SFT, all end-to-end RL runs fail to improve. More specifically, we observe that without SFT, the base model suffers from poor instruction following capability. A detailed failure case is provided in [Figure 20](https://arxiv.org/html/2501.17161v2#A4.F20 "In RL cannot save overfitted checkpoints. ‣ D.3 Failure Cases ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") (in [Section D.3](https://arxiv.org/html/2501.17161v2#A4.SS3 "D.3 Failure Cases ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")), revealing that the base Llama-3.2-Vision-11B model tends to generate long, tangential, and unstructured responses. This issue makes it impossible to retrieve task-related information and rewards for RL training. Note that due to the difference in backbone model, our results do not contradict with DeepSeekAI et al. ([2025](https://arxiv.org/html/2501.17161v2#bib.bib16 "")), which suggests that SFT is unnecessary for downstream RL training.

### 5.5 Role of Verification Iterations

Verification serves as another crucial component in our multi-step training and evaluation pipeline (see [Figures 2](https://arxiv.org/html/2501.17161v2#S3.F2 "In Sequential revision. ‣ 3 Preliminaries ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [3](https://arxiv.org/html/2501.17161v2#S3.F3 "Figure 3 ‣ Sequential revision. ‣ 3 Preliminaries ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). To validate its necessity and better understand its effect, we conduct RL experiments with different verification iterations {1,3,5,10}13510\\{1,3,5,10\\}{ 1 , 3 , 5 , 10 } using GP-L ([Figure 10](https://arxiv.org/html/2501.17161v2#S5.F10 "In 5.5 Role of Verification Iterations ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

![Refer to caption](x9.png)

Figure 10: In-distribution vs. OOD performance growth on GP-L. We record RL experiments with different number of verification iterations (VIter) as scaling up training compute (color transparency).

#### Scaling up verification improves generalization.

In [Figure 10](https://arxiv.org/html/2501.17161v2#S5.F10 "In 5.5 Role of Verification Iterations ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we observe that RL generalizes better with more verification steps. More specifically, under the same computational budget across all experiments, we observe improvements of +2.15% (3 steps), +2.99% (5 steps), +5.99% (10 steps). In contrast, in the case with one verification step, we only observe a marginal improvement of +0.48% in OOD performance improvement.

## 6 Conclusion, Discussion, and Limitations

In this paper, we present a comprehensive analysis of the generalization effects of foundation model post-training techniques, specifically RL and SFT. Through extensive experiments on the GeneralPoints and V-IRL tasks, we demonstrated that RL exhibits superior performance in learning generalizable knowledge, while SFT tends to merely memorize the training data, across both the rule and visual variations. This phenomenon consistently occurs across multimodal arithmetic and spatial reasoning capabilities. In addition, we studied the effect of RL on visual recognition, the role of SFT, and the role of verification steps. During our study, two challenges were not resolved.

#### Failure of SFT on GP-VL.

In [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") for GP-VL, we observe that SFT fails to achieve a comparable in-distribution performance with RL. To mitigate the variance introduced by hyperparameter choices, we additionally conduct 10 more experiments with different learning rates and tunable components ([Figure 16](https://arxiv.org/html/2501.17161v2#A3.F16 "In Computation estimation. ‣ C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")), none of which exhibits a strong increasing trend like RL ([Figure 17](https://arxiv.org/html/2501.17161v2#A4.F17 "In RL. ‣ D.1 Ablation Studies on GP-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). Given our observation that scaling up SFT degrades visual recognition capabilities ([Figure 8](https://arxiv.org/html/2501.17161v2#S5.F8 "In RL generalizes, SFT memorizes. ‣ 5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")), we hypothesize that SFT locally overfits to reasoning tokens while neglecting recognition tokens, possibly due to the higher frequency of reasoning tokens (see [Figure 11](https://arxiv.org/html/2501.17161v2#A1.F11 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") as example). We leave further investigation to future work.

#### Limits of RL in corner cases.

As discussed in  [Section 5.4](https://arxiv.org/html/2501.17161v2#S5.SS4 "5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), SFT is necessary for effective RL training on Llama-3.2. We investigate applying RL to an overly-tuned SFT checkpoint. As demonstrated in [Figure 19](https://arxiv.org/html/2501.17161v2#A4.F19 "In D.2 More results on V-IRL-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), RL is unable to recover out-of-distribution performance when starting from such a checkpoint. Example failure cases are illustrated in [Figure 21](https://arxiv.org/html/2501.17161v2#A4.F21 "In RL cannot save overfitted checkpoints. ‣ D.3 Failure Cases ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), where the model collapses to the training rule. These results, together with findings in [Section 5.4](https://arxiv.org/html/2501.17161v2#S5.SS4 "5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), indicate that RL has limited effectiveness when applied to extremely underfit or overfit initial checkpoints. Further research is needed to delineate the conditions under which SFT facilitates effective RL.

## Impact Statement

This paper presents work aimed at advancing the field of Machine Learning. While the study includes tasks such as GeneralPoints, which is a synthetic environment, and V-IRL, a real-world map simulator, our work is confined to controlled research settings. The V-IRL environment is designed as a simulated proxy for real-world tasks, but no deployment or interaction with actual real-world systems or data was involved. The methods, environments, and tasks investigated in this study were constructed to advance our understanding of model generalization without introducing any foreseeable societal or ethical implications.

## Acknowledgements

YZ would like to thank Xiaoxuan Feng for beautifying Figure [4](https://arxiv.org/html/2501.17161v2#S4.F4 "Figure 4 ‣ Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). We would like to thank Jincheng Mei and Doina Precup for feedbacks on earlier manuscripts. Yi Ma would like to acknowledge support from the joint Simons Foundation-NSF DMS grant #2031899, the ONR grant N00014-22-1-2102, the NSF grant #2402951, and also support from and the HKU startup, the Hong Kong Center for Construction Robotics Limited (HKCRC) Award 052245, and JC Club of Hong Kong.

## References

*   Abdulhai et al. (2023) Abdulhai, M., White, I., Snell, C., Sun, C., Hong, J., Zhai, Y., Xu, K., and Levine, S. LMRL Gym: Benchmarks for multi-turn reinforcement learning with language models. *arXiv preprint arXiv:2311.18232*, 2023.
*   Agarwal et al. (2019) Agarwal, A., Jiang, N., Kakade, S. M., and Sun, W. Reinforcement learning: Theory and algorithms. *CS Dept., UW Seattle, Seattle, WA, USA, Tech. Rep*, 32, 2019.
*   Allen-Zhu (2024) Allen-Zhu, Z. ICML 2024 Tutorial: Physics of Language Models, July 2024. Project page: [https://physics.allen-zhu.com/](https://physics.allen-zhu.com/ "").
*   Allen-Zhu & Li (2023a) Allen-Zhu, Z. and Li, Y. Physics of language models: Part 3.1, knowledge storage and extraction. *arXiv preprint arXiv:2309.14316*, 2023a.
*   Allen-Zhu & Li (2023b) Allen-Zhu, Z. and Li, Y. Physics of language models: Part 3.2, knowledge manipulation. *arXiv preprint arXiv:2309.14402*, 2023b.
*   Allen-Zhu & Li (2024) Allen-Zhu, Z. and Li, Y. Physics of language models: Part 3.3, knowledge capacity scaling laws. *arXiv preprint arXiv:2404.05405*, 2024.
*   Bommasani et al. (2021) Bommasani, R., Hudson, D. A., Adeli, E., Altman, R., Arora, S., von Arx, S., Bernstein, M. S., Bohg, J., Bosselut, A., Brunskill, E., et al. On the opportunities and risks of foundation models. *arXiv preprint arXiv:2108.07258*, 2021.
*   Bousquet & Elisseeff (2000) Bousquet, O. and Elisseeff, A. Algorithmic stability and generalization performance. volume 13, 2000.
*   Brown et al. (2020) Brown, T., Mann, B., Ryder, N., Subbiah, M., Kaplan, J. D., Dhariwal, P., Neelakantan, A., Shyam, P., Sastry, G., Askell, A., et al. Language models are few-shot learners. *Advances in neural information processing systems*, 33:1877–1901, 2020.
*   Carlini et al. (2022) Carlini, N., Ippolito, D., Jagielski, M., Lee, K., Tramer, F., and Zhang, C. Quantifying memorization across neural language models. *arXiv preprint arXiv:2202.07646*, 2022.
*   Chen et al. (2024a) Chen, G., Liao, M., Li, C., and Fan, K. AlphaMath almost zero: Process supervision without process. *arXiv preprint arXiv:2405.03553*, 2024a.
*   Chen et al. (2024b) Chen, J., Han, X., Ma, Y., Zhou, X., and Xiang, L. Unlock the correlation between supervised fine-tuning and reinforcement learning in training code large language models. *arXiv preprint arXiv:2406.10305*, 2024b.
*   Chen et al. (2023) Chen, L., Li, J., Dong, X., Zhang, P., He, C., Wang, J., Zhao, F., and Lin, D. ShareGPT4V: Improving large multi-modal models with better captions. *arXiv preprint arXiv:2311.12793*, 2023.
*   Chung et al. (2022) Chung, H. W., Hou, L., Longpre, S., Zoph, B., Tay, Y., Fedus, W., Li, E., Wang, X., Dehghani, M., Brahma, S., et al. Scaling instruction-finetuned language models. *arXiv preprint arXiv:2210.11416*, 2022.
*   Cobbe et al. (2021) Cobbe, K., Kosaraju, V., Bavarian, M., Chen, M., Jun, H., Kaiser, L., Plappert, M., Tworek, J., Hilton, J., Nakano, R., et al. Training verifiers to solve math word problems. *arXiv preprint arXiv:2110.14168*, 2021.
*   DeepSeekAI et al. (2025) DeepSeekAI et al. DeepSeek-R1: Incentivizing reasoning capability in LLMs via reinforcement learning, 2025. URL [https://arxiv.org/abs/2501.12948](https://arxiv.org/abs/2501.12948 "").
*   Dubey et al. (2024) Dubey, A., Jauhri, A., Pandey, A., Kadian, A., Al-Dahle, A., Letman, A., Mathur, A., Schelten, A., Yang, A., Fan, A., et al. The Llama 3 Herd of models. *arXiv preprint arXiv:2407.21783*, 2024.
*   Feng et al. (2023) Feng, X., Wan, Z., Wen, M., McAleer, S. M., Wen, Y., Zhang, W., and Wang, J. AlphaZero-like tree-search can guide large language model decoding and training. *arXiv preprint arXiv:2309.17179*, 2023.
*   Google (2023) Google, D. Introducing Gemini: Our largest and most capable AI model, 2023. URL [https://blog.google/technology/ai/google-gemini-ai/](https://blog.google/technology/ai/google-gemini-ai/ "").
*   Han et al. (2022) Han, J., Zhan, H., Hong, J., Fang, P., Li, H., Petersson, L., and Reid, I. What images are more memorable to machines? *arXiv preprint arXiv:2211.07625*, 2022.
*   Hoffmann et al. (2023) Hoffmann, J., Borgeaud, S., Mensch, A., Buchatskaya, E., Cai, T., Rutherford, E., Casas, D. d. L., Hendricks, L. A., Welbl, J., Clark, A., et al. Training compute-optimal large language models. *NeurIPS*, 2023.
*   Hosseini et al. (2024) Hosseini, A., Yuan, X., Malkin, N., Courville, A., Sordoni, A., and Agarwal, R. V-STar: Training verifiers for self-taught reasoners. In *First Conference on Language Modeling*, 2024. URL [https://openreview.net/forum?id=stmqBSW2dV](https://openreview.net/forum?id=stmqBSW2dV "").
*   Jaech et al. (2024) Jaech, A., Kalai, A., Lerer, A., Richardson, A., El-Kishky, A., Low, A., Helyar, A., Madry, A., Beutel, A., Carney, A., et al. OpenAI o1 system card. *arXiv preprint arXiv:2412.16720*, 2024.
*   Jiang et al. (2024) Jiang, M., Liu, K. Z., Zhong, M., Schaeffer, R., Ouyang, S., Han, J., and Koyejo, S. Investigating data contamination for pre-training language models. *arXiv preprint arXiv:2401.06059*, 2024.
*   Kang et al. (2024) Kang, K., Setlur, A., Ghosh, D., Steinhardt, J., Tomlin, C., Levine, S., and Kumar, A. What do learning dynamics reveal about generalization in LLM reasoning? *arXiv preprint arXiv:2411.07681*, 2024.
*   Kar et al. (2025) Kar, O. F., Tonioni, A., Poklukar, P., Kulshrestha, A., Zamir, A., and Tombari, F. Brave: Broadening the visual encoding of vision-language models. In *European Conference on Computer Vision*, pp.  113–132. Springer, 2025.
*   Liu et al. (2023) Liu, H., Li, C., Li, Y., and Lee, Y. J. Improved baselines with visual instruction tuning. *arXiv preprint arXiv:2310.03744*, 2023.
*   Liu et al. (2024) Liu, H., Li, C., Li, Y., Li, B., Zhang, Y., Shen, S., and Lee, Y. J. LLaVA-NeXT: Improved reasoning, ocr, and world knowledge, 2024. URL [https://llava-vl.github.io/blog/2024-01-30-llava-next/](https://llava-vl.github.io/blog/2024-01-30-llava-next/ "").
*   Lu et al. (2023) Lu, P., Bansal, H., Xia, T., Liu, J., Li, C., Hajishirzi, H., Cheng, H., Chang, K.-W., Galley, M., and Gao, J. MathVista: Evaluating mathematical reasoning of foundation models in visual contexts. *ICLR*, 2023.
*   OpenAI (2023a) OpenAI. GPT-4, 2023a. URL [https://openai.com/research/gpt-4](https://openai.com/research/gpt-4 "").
*   OpenAI (2023b) OpenAI. GPT-4 technical report. *arXiv*, pp.  2303–08774, 2023b.
*   Ouyang et al. (2022) Ouyang, L., Wu, J., Jiang, X., Almeida, D., Wainwright, C., Mishkin, P., Zhang, C., Agarwal, S., Slama, K., Ray, A., et al. Training language models to follow instructions with human feedback. In *NeurIPS*, 2022.
*   Qi et al. (2024) Qi, Z., Luo, H., Huang, X., Zhao, Z., Jiang, Y., Fan, X., Lakkaraju, H., and Glass, J. Quantifying generalization complexity for large language models. *arXiv preprint arXiv:2410.01769*, 2024.
*   Radford et al. (2018) Radford, A., Narasimhan, K., Salimans, T., Sutskever, I., et al. Improving language understanding by generative pre-training. 2018.
*   Radford et al. (2021) Radford, A., Kim, J. W., Hallacy, C., Ramesh, A., Goh, G., Agarwal, S., Sastry, G., Askell, A., Mishkin, P., Clark, J., et al. Learning transferable visual models from natural language supervision. In *International conference on machine learning*, pp.  8748–8763. PMLR, 2021.
*   Rahmanzadehgervi et al. (2024) Rahmanzadehgervi, P., Bolton, L., Taesiri, M. R., and Nguyen, A. T. Vision language models are blind. In *Proceedings of the Asian Conference on Computer Vision*, pp.  18–34, 2024.
*   Ramamurthy et al. (2023) Ramamurthy, R., Ammanabrolu, P., Brantley, K., Hessel, J., Sifa, R., Bauckhage, C., Hajishirzi, H., and Choi, Y. Is reinforcement learning (not) for natural language processing: Benchmarks, baselines, and building blocks for natural language policy optimization. In *The Eleventh International Conference on Learning Representations*, 2023. URL [https://openreview.net/forum?id=8aHzds2uUyB](https://openreview.net/forum?id=8aHzds2uUyB "").
*   Schulman et al. (2017) Schulman, J., Wolski, F., Dhariwal, P., Radford, A., and Klimov, O. Proximal policy optimization algorithms. *arXiv preprint arXiv:1707.06347*, 2017.
*   Setlur et al. (2024) Setlur, A., Nagpal, C., Fisch, A., Geng, X., Eisenstein, J., Agarwal, R., Agarwal, A., Berant, J., and Kumar, A. Rewarding progress: Scaling automated process verifiers for LLM reasoning. *arXiv preprint arXiv:2410.08146*, 2024.
*   Snell et al. (2024) Snell, C., Lee, J., Xu, K., and Kumar, A. Scaling LLM test-time compute optimally can be more effective than scaling model parameters. *arXiv preprint arXiv:2408.03314*, 2024.
*   Sun et al. (2024) Sun, Z., Shen, S., Cao, S., Liu, H., Li, C., Shen, Y., Gan, C., Gui, L., Wang, Y.-X., Yang, Y., Keutzer, K., and Darrell, T. Aligning large multimodal models with factually augmented RLHF. In Ku, L.-W., Martins, A., and Srikumar, V. (eds.), *Findings of the Association for Computational Linguistics: ACL 2024*, pp.  13088–13110, Bangkok, Thailand, August 2024. Association for Computational Linguistics. doi: 10.18653/v1/2024.findings-acl.775. URL [https://aclanthology.org/2024.findings-acl.775](https://aclanthology.org/2024.findings-acl.775 "").
*   Sutton & Barto (2018) Sutton, R. S. and Barto, A. G. *Reinforcement Learning: An Introduction*. MIT press, 2018.
*   Tian et al. (2024) Tian, Y., Peng, B., Song, L., Jin, L., Yu, D., Mi, H., and Yu, D. Toward self-improvement of LLMs via imagination, searching, and criticizing. *arXiv preprint arXiv:2404.12253*, 2024.
*   Tong et al. (2024a) Tong, S., Brown, E., Wu, P., Woo, S., Middepogu, M., Akula, S. C., Yang, J., Yang, S., Iyer, A., Pan, X., et al. Cambrian-1: A fully open, vision-centric exploration of multimodal LLMs. In *NeurIPS*, 2024a.
*   Tong et al. (2024b) Tong, S., Fan, D., Zhu, J., Xiong, Y., Chen, X., Sinha, K., Rabbat, M., LeCun, Y., Xie, S., and Liu, Z. Metamorph: Multimodal understanding and generation via instruction tuning. *arXiv preprint arXiv:2412.14164*, 2024b.
*   Tong et al. (2024c) Tong, S., Jones, E., and Steinhardt, J. Mass-producing failures of multimodal systems with language models. In *NeurIPS*, 2024c.
*   Tong et al. (2024d) Tong, S., Liu, Z., Zhai, Y., Ma, Y., LeCun, Y., and Xie, S. Eyes wide shut? Exploring the visual shortcomings of multimodal LLMs. In *CVPR*, 2024d.
*   Touvron et al. (2023) Touvron, H., Lavril, T., Izacard, G., Martinet, X., Lachaux, M.-A., Lacroix, T., Rozière, B., Goyal, N., Hambro, E., Azhar, F., et al. Llama: Open and efficient foundation language models. *arXiv preprint arXiv:2302.13971*, 2023.
*   Wang et al. (2024) Wang, X., Antoniades, A., Elazar, Y., Amayuelas, A., Albalak, A., Zhang, K., and Wang, W. Y. Generalization vs memorization: Tracing language models’ capabilities back to pretraining data. *arXiv preprint arXiv:2407.14985*, 2024.
*   Wei et al. (2022a) Wei, J., Bosma, M., Zhao, V., Guu, K., Yu, A. W., Lester, B., Du, N., Dai, A. M., and Le, Q. V. Finetuned language models are zero-shot learners. In *International Conference on Learning Representations*, 2022a. URL [https://openreview.net/forum?id=gEZrGCozdqR](https://openreview.net/forum?id=gEZrGCozdqR "").
*   Wei et al. (2022b) Wei, J., Wang, X., Schuurmans, D., Bosma, M., Xia, F., Chi, E., Le, Q. V., Zhou, D., et al. Chain-of-thought prompting elicits reasoning in large language models. *Advances in Neural Information Processing Systems*, 35:24824–24837, 2022b.
*   Yang et al. (2024a) Yang, J., Ding, R., Brown, E., Qi, X., and Xie, S. V-IRL: Grounding virtual intelligence in real life. In *European conference on computer vision*, 2024a.
*   Yang et al. (2024b) Yang, J., Yang, S., Gupta, A. W., Han, R., Fei-Fei, L., and Xie, S. Thinking in space: How multimodal large language models see, remember, and recall spaces. *arXiv preprint arXiv:2412.14171*, 2024b.
*   Yang et al. (2023) Yang, Z., Lukasik, M., Nagarajan, V., Li, Z., Rawat, A. S., Zaheer, M., Menon, A. K., and Kumar, S. ResMem: Learn what you can and memorize the rest. In *Thirty-seventh Conference on Neural Information Processing Systems*, 2023. URL [https://openreview.net/forum?id=HFQFAyNucq](https://openreview.net/forum?id=HFQFAyNucq "").
*   Yao et al. (2024) Yao, S., Yu, D., Zhao, J., Shafran, I., Griffiths, T., Cao, Y., and Narasimhan, K. Tree of thoughts: Deliberate problem solving with large language models. *Advances in Neural Information Processing Systems*, 36, 2024.
*   Ye et al. (2024) Ye, T., Xu, Z., Li, Y., and Allen-Zhu, Z. Physics of language models: Part 2.1, grade-school math and the hidden reasoning process. *arXiv preprint arXiv:2407.20311*, 2024.
*   Yue et al. (2024a) Yue, X., Ni, Y., Zhang, K., Zheng, T., Liu, R., Zhang, G., Stevens, S., Jiang, D., Ren, W., Sun, Y., et al. MMMU: A massive multi-discipline multimodal understanding and reasoning benchmark for expert AGI. In *CVPR*, 2024a.
*   Yue et al. (2024b) Yue, X., Zheng, T., Ni, Y., Wang, Y., Zhang, K., Tong, S., Sun, Y., Yin, M., Yu, B., Zhang, G., et al. MMMU-Pro: A more robust multi-discipline multimodal understanding benchmark. *arXiv preprint arXiv:2409.02813*, 2024b.
*   Zelikman et al. (2022) Zelikman, E., Wu, Y., Mu, J., and Goodman, N. STaR: Bootstrapping reasoning with reasoning. *Advances in Neural Information Processing Systems*, 35:15476–15488, 2022.
*   Zhai et al. (2024a) Zhai, Y., Bai, H., Lin, Z., Pan, J., Tong, S., Zhou, Y., Suhr, A., Xie, S., LeCun, Y., Ma, Y., and Levine, S. Fine-tuning large vision-language models as decision-making agents via reinforcement learning. In *The Thirty-eighth Annual Conference on Neural Information Processing Systems*, 2024a. URL [https://openreview.net/forum?id=nBjmMF2IZU](https://openreview.net/forum?id=nBjmMF2IZU "").
*   Zhai et al. (2024b) Zhai, Y., Tong, S., Li, X., Cai, M., Qu, Q., Lee, Y. J., and Ma, Y. Investigating the catastrophic forgetting in multimodal large language model fine-tuning. In *Conference on Parsimony and Learning*, pp.  202–227. PMLR, 2024b.
*   Zhang et al. (2021) Zhang, C., Bengio, S., Hardt, M., Recht, B., and Vinyals, O. Understanding deep learning (still) requires rethinking generalization. *Communications of the ACM*, 64(3):107–115, 2021.
*   Zhang et al. (2023) Zhang, C., Ippolito, D., Lee, K., Jagielski, M., Tramèr, F., and Carlini, N. Counterfactual memorization in neural language models. *Advances in Neural Information Processing Systems*, 36:39321–39362, 2023.
*   Zhang et al. (2022) Zhang, S., Roller, S., Goyal, N., Artetxe, M., Chen, M., Chen, S., Dewan, C., Diab, M., Li, X., Lin, X. V., et al. Opt: Open pre-trained transformer language models. *arXiv preprint arXiv:2205.01068*, 2022.
*   Zhong et al. (2024) Zhong, M., Zhang, A., Wang, X., Hou, R., Xiong, W., Zhu, C., Chen, Z., Tan, L., Bi, C., Lewis, M., et al. Law of the weakest link: Cross capabilities of large language models. *arXiv preprint arXiv:2409.19951*, 2024.
*   Zhou et al. (2024a) Zhou, C., Liu, P., Xu, P., Iyer, S., Sun, J., Mao, Y., Ma, X., Efrat, A., Yu, P., Yu, L., et al. LIMA: Less is more for alignment. *Advances in Neural Information Processing Systems*, 36, 2024a.
*   Zhou et al. (2024b) Zhou, Y., Zanette, A., Pan, J., Levine, S., and Kumar, A. ArCHer: Training language model agents via hierarchical multi-turn RL. *arXiv preprint arXiv:2402.19446*, 2024b.
*   Zhu et al. (2023) Zhu, Z., Xue, Y., Chen, X., Zhou, D., Tang, J., Schuurmans, D., and Dai, H. Large language models can learn rules. *arXiv preprint arXiv:2310.07064*, 2023.
*   Ziegler et al. (2019) Ziegler, D. M., Stiennon, N., Wu, J., Brown, T. B., Radford, A., Amodei, D., Christiano, P., and Irving, G. Fine-tuning language models from human preferences. *arXiv preprint arXiv:1909.08593*, 2019.

## Appendix A Details on the General Points Environment

In this section, we demonstrate the design details for GeneralPoints mentioned in [Section 4.1](https://arxiv.org/html/2501.17161v2#S4.SS1 "4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). We first present the data used for this environment ([Section A.1](https://arxiv.org/html/2501.17161v2#A1.SS1 "A.1 Data ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). Then, we show examples of the environment’s transition dynamics ([Section A.2](https://arxiv.org/html/2501.17161v2#A1.SS2 "A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")), followed by a description of key arguments and reward design specification ([Section A.3](https://arxiv.org/html/2501.17161v2#A1.SS3 "A.3 Additional Eetails on the Environmental Design ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

### A.1 Data

GeneralPoints card quadruples are sampled from a deck of 52 standard poker cards. Each sampled quadruple is guaranteed to have at least one solution equals the target point, i.e. 24. We ensure this by using an expert solver during the sampling process.

### A.2 Detailed Examples on the Transition Dynamics

As shown in [Figure 11](https://arxiv.org/html/2501.17161v2#A1.F11 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [Figure 12](https://arxiv.org/html/2501.17161v2#A1.F12 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we treat the system prompt as 𝐯0insubscriptsuperscript𝐯in0\\mathbf{v}^{\\text{in}}\_{0}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT 0 end\_POSTSUBSCRIPT and then subsequently appending the future outputs 𝐯1:toutsubscriptsuperscript𝐯out:1𝑡\\mathbf{v}^{\\text{out}}\_{1:t}bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT 1 : italic\_t end\_POSTSUBSCRIPT and verifier info 𝐯1:tversubscriptsuperscript𝐯ver:1𝑡\\mathbf{v}^{\\text{ver}}\_{1:t}bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT 1 : italic\_t end\_POSTSUBSCRIPT into the prompt for getting the t+1𝑡1t+1italic\_t + 1 output. [Figure 11](https://arxiv.org/html/2501.17161v2#A1.F11 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") provides an example with the visual inputs, while [Figure 12](https://arxiv.org/html/2501.17161v2#A1.F12 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") shows the language only case.

Figure 11: An example of our prompt update for constructing 𝐯t+1insubscriptsuperscript𝐯in𝑡1\\mathbf{v}^{\\text{in}}\_{t+1}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t + 1 end\_POSTSUBSCRIPT using 𝐯tin,𝐯toutsubscriptsuperscript𝐯in𝑡subscriptsuperscript𝐯out𝑡\\mathbf{v}^{\\text{in}}\_{t},\\mathbf{v}^{\\text{out}}\_{t}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT and 𝐯tversubscriptsuperscript𝐯ver𝑡\\mathbf{v}^{\\text{ver}}\_{t}bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT. This example provides an optional vision input for VLMs, adding a visual recognition challenge. The brown parts marks the task and related information, and the purple parts denote the state (st)subscript𝑠𝑡(s\_{t})( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) specific info. The blue and red describe the output from the model and verifier, respectively. 

Figure 12: An example of our prompt update for constructing 𝐯t+1insubscriptsuperscript𝐯in𝑡1\\mathbf{v}^{\\text{in}}\_{t+1}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t + 1 end\_POSTSUBSCRIPT using 𝐯tin,𝐯toutsubscriptsuperscript𝐯in𝑡subscriptsuperscript𝐯out𝑡\\mathbf{v}^{\\text{in}}\_{t},\\mathbf{v}^{\\text{out}}\_{t}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT and 𝐯tversubscriptsuperscript𝐯ver𝑡\\mathbf{v}^{\\text{ver}}\_{t}bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT. This example provides an optional vision input for VLMs, adding a visual recognition challenge. The brown parts marks the task and related information, and the purple parts denote the state (st)subscript𝑠𝑡(s\_{t})( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) specific info. The blue and red describe the output from the model and verifier, respectively. 

### A.3 Additional Eetails on the Environmental Design

#### Arguments.

The GeneralPoints environment supports the following configurable arguments:

*   •

    Target point: Any positive integer

*   •

    Face cards rule: Two options

    *   –

        'J', 'Q', and 'K' all count as '10'

    *   –

        'J', 'Q', and 'K' count as '11', '12', and '13' respectively

*   •

    Card sampling: Two options

    *   –

        Sample 4 cards without replacement from a deck of 52 poker cards

    *   –

        Sample at least one card from 'J', 'Q', and 'K'

*   •

    Card color: Three options

    *   –

        Black suits only: ♣, ♠.

    *   –

        Red suits only: ♥, ♠.

    *   –

        All suits: ♠, ♥, ♣, ♠.

For all experiments, we fix the target point at 24. In [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), training and in-domain evaluation use the rule where face cards count as '10'. For out-of-domain evaluation, we use the alternative face cards rule and require at least one face card, forcing calculations with numbers above 10 that are not encountered during training. For visual distribution shift experiments ([Section 5.2](https://arxiv.org/html/2501.17161v2#S5.SS2 "5.2 Generalization in Visual Out-of-Distribution Tasks ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")), we train the model on black suits ♠, ♣ and evaluate out-of-domain performance on red suits ♥, ♠.

#### Reward design.

An episode terminates when either a correct equation is generated or the maximum verification step of 5555 is reached. The reward function is as follows:

*   •

    r\=5𝑟5r=5italic\_r = 5: For generating a legal equation that equals the target point

*   •

    r\=−1𝑟1r=-1italic\_r = - 1: For legal equations using each card once but not equaling the target point

*   •

    r\=−1𝑟1r=-1italic\_r = - 1: For exceeding maximum verification step

*   •

    r\=−2𝑟2r=-2italic\_r = - 2: For legal equations containing numbers not among the given choices

*   •

    r\=−3𝑟3r=-3italic\_r = - 3: For all other illegal equations

In the vision-language variant (GeneralPoints-VL), an additional penalty of r\=−1.5𝑟1.5r=-1.5italic\_r = - 1.5 is applied when the agent fails to correctly recognize the given cards.

## Appendix B Details on the V-IRL Environment

Similar to [Appendix A](https://arxiv.org/html/2501.17161v2#A1 "Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we present the design details for V-IRL discussed in [Section 4.2](https://arxiv.org/html/2501.17161v2#S4.SS2 "4.2 The V-IRL Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). First, we introduce the database used for this environment ([Section B.1](https://arxiv.org/html/2501.17161v2#A2.SS1 "B.1 Data ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")) and demonstrate transition examples ([Section B.2](https://arxiv.org/html/2501.17161v2#A2.SS2 "B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). We then describe the environment by explaining its fundamental component—route. Finally, we outline our modifications and reward design choices made to adapt the original V-IRL for reinforcement learning training ([Section B.3](https://arxiv.org/html/2501.17161v2#A2.SS3 "B.3 Additional Details on the Environmental Design ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

### B.1 Data

Leveraging the data collection pipeline of Yang et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")), we construct a training database with 1000 unique routes from New York City. We evaluate all rule-variant experiments and visual in-distribution experiments using randomly sampled routes from this database. For visual out-of-distribution experiments, we directly adopt the VLN mini benchmark from Yang et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")). This benchmark consists of 18 distinct routes across nine cities: Milan, New Delhi, Buenos Aires, London, Hong Kong, New York,444These NYC routes in the VLN mini benchmark do not overlap with our training data. Melbourne, Lagos, and San Francisco, with two routes per city.

### B.2 Detailed Examples on the Transition Dynamics

We provide detailed transition examples of the V-IRL environment in [Figure 13](https://arxiv.org/html/2501.17161v2#A2.F13 "In B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") (vision and language) and [Figure 14](https://arxiv.org/html/2501.17161v2#A2.F14 "In B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") (pure language).

Figure 13: An example of our prompt update for constructing 𝐯t+1insubscriptsuperscript𝐯in𝑡1\\mathbf{v}^{\\text{in}}\_{t+1}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t + 1 end\_POSTSUBSCRIPT using 𝐯tin,𝐯toutsubscriptsuperscript𝐯in𝑡subscriptsuperscript𝐯out𝑡\\mathbf{v}^{\\text{in}}\_{t},\\mathbf{v}^{\\text{out}}\_{t}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT and 𝐯tversubscriptsuperscript𝐯ver𝑡\\mathbf{v}^{\\text{ver}}\_{t}bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT. This example provides an optional vision input for VLMs, adding a visual recognition challenge. The brown parts marks the task and related information, and the purple parts denote the state (st)subscript𝑠𝑡(s\_{t})( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) specific info. The blue and red describe the output from the model and verifier, respectively.

Figure 14: An example of our prompt update for constructing 𝐯t+1insubscriptsuperscript𝐯in𝑡1\\mathbf{v}^{\\text{in}}\_{t+1}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t + 1 end\_POSTSUBSCRIPT using 𝐯tin,𝐯toutsubscriptsuperscript𝐯in𝑡subscriptsuperscript𝐯out𝑡\\mathbf{v}^{\\text{in}}\_{t},\\mathbf{v}^{\\text{out}}\_{t}bold\_v start\_POSTSUPERSCRIPT in end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT , bold\_v start\_POSTSUPERSCRIPT out end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT and 𝐯tversubscriptsuperscript𝐯ver𝑡\\mathbf{v}^{\\text{ver}}\_{t}bold\_v start\_POSTSUPERSCRIPT ver end\_POSTSUPERSCRIPT start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT. The brown parts marks the task and related information, and the purple parts denote the state (st)subscript𝑠𝑡(s\_{t})( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) specific info. The brown parts marks the task and related information, and the purple parts denote the state (st)subscript𝑠𝑡(s\_{t})( italic\_s start\_POSTSUBSCRIPT italic\_t end\_POSTSUBSCRIPT ) specific info. The blue and red describe the output from the model and verifier, respectively. 

### B.3 Additional Details on the Environmental Design

#### Concept of route.

The route serves as the fundamental navigation object in the V-IRL environment. As illustrated in [Figure 4](https://arxiv.org/html/2501.17161v2#S4.F4 "In Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), each route corresponds to a real-world path with associated language instructions and visual signals. Using [Figure 4](https://arxiv.org/html/2501.17161v2#S4.F4 "In Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") as an example, a route comprises:

*   •

    Destination: Shuka

*   •

    Starting point: Start

*   •

    Turning points: The Dutch, Lola Taverna

*   •

    Straight road: Roads connecting turning points, starting point, and destination

*   •

    Street views: 360-degree panoramic views at each movable point

*   •

    Oracle information: Expert observation data for each movable point

*   •

    Expert trajectory

*   •

    Instruction

Although the instructions in [Figures 4](https://arxiv.org/html/2501.17161v2#S4.F4 "In Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), [14](https://arxiv.org/html/2501.17161v2#A2.F14 "Figure 14 ‣ B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [13](https://arxiv.org/html/2501.17161v2#A2.F13 "Figure 13 ‣ B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") are presented in different formats, they convey equivalent information, with [Figure 4](https://arxiv.org/html/2501.17161v2#S4.F4 "In Visual variations. ‣ 4.1 The General Points Environment ‣ 4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") using natural language.

#### Simplification and arguments.

We simplify the original V-IRL design from Yang et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")) to better accommodate RL training. The modifications include eliminating the 2-stage navigation pipeline that required a separate visual detector for street view processing, and removing online queries to reduce training time and cost. Our V-IRL environment contains 2 additional configuration arguments compared with the original design:

*   •

    Action space: two options

    *   –

        Absolute direction:
        "turn\_direction(x)" where x∈\\in∈{'north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'}, "forward()", "stop()"

    *   –

        Relative direction:
        "turn\_direction(x)" where x∈\\in∈{'left', 'right', 'slightly left', 'slightly right'}, "forward()", "stop()"

*   •

    Maximum straight road length: any positive integer

The action space argument accommodates the rule variants described in [Section 4](https://arxiv.org/html/2501.17161v2#S4 "4 Evaluation Tasks ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). For experiments shown in [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we use absolute direction action space during training and in-domain evaluation, while using the alternative rule for out-of-domain evaluation. We implement a maximum straight road length to limit the number of movable coordinates between turning points, preventing sequences of repetitive "forward()" actions. We conduct visual distribution shift experiments ([Section 5.2](https://arxiv.org/html/2501.17161v2#S5.SS2 "5.2 Generalization in Visual Out-of-Distribution Tasks ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")) via training the model on New York City regions and evaluating the out-of-domain performance on the worldwide navigation routes from the benchmark released by Yang et al. ([2024a](https://arxiv.org/html/2501.17161v2#bib.bib52 "")).

#### Reward design.

An episode terminates when either the navigation agent stops at the destination or the maximum verification step of 2 is reached. The reward function is as follows:

*   •

    r\=1𝑟1r=1italic\_r = 1: For generating a correct action at the current coordinate

*   •

    r\=−1𝑟1r=-1italic\_r = - 1: For generating wrong action at the current coordinate

*   •

    r\=−1𝑟1r=-1italic\_r = - 1: For exceeding maximum verification step

*   •

    r\=−1.5𝑟1.5r=-1.5italic\_r = - 1.5: For failed detection of landmarks

## Appendix C Experimental Setup

This section details the experimental setup used in [Section 5](https://arxiv.org/html/2501.17161v2#S5 "5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). We first describe our data collection setup for supervised fine-tuning ([Section C.1](https://arxiv.org/html/2501.17161v2#A3.SS1 "C.1 Data ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). Then, we present the training pipeline ([Section C.2](https://arxiv.org/html/2501.17161v2#A3.SS2 "C.2 Training Pipeline ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")). Finally, we describe our evaluation metrics and the statistical tools used for generating plots ([Section C.3](https://arxiv.org/html/2501.17161v2#A3.SS3 "C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training")).

### C.1 Data

#### SFT data collection.

As illustrated in [Figures 12](https://arxiv.org/html/2501.17161v2#A1.F12 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), [11](https://arxiv.org/html/2501.17161v2#A1.F11 "Figure 11 ‣ A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), [14](https://arxiv.org/html/2501.17161v2#A2.F14 "Figure 14 ‣ B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [13](https://arxiv.org/html/2501.17161v2#A2.F13 "Figure 13 ‣ B.2 Detailed Examples on the Transition Dynamics ‣ Appendix B Details on the V-IRL Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), GeneralPoints and V-IRL environments naturally align with prompt-response dialogue structures. We create training samples by pairing each system prompt with its corresponding expert response. All SFT experiments in the main body use optimal single-turn prompt-response pairs, without any verification or revision steps.

#### SFT on sub-optimal trajectories

To examine how more diverse SFT data affects the out-of-distribution performance of SFT, we conduct an ablation study on GP-L using sub-optimal trajectories as training data. Unlike expert prompt-response pairs, these sub-optimal trajectories include errors and verification messages in their prompts. This format aligns with evaluation scenarios where multiple verification iterations are allowed, similar to the data being used for the downstream RL training. In [Figure 15](https://arxiv.org/html/2501.17161v2#A3.F15 "In SFT on sub-optimal trajectories ‣ C.1 Data ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we observe that SFT still merely memorizes the training data with degraded out-of-distribution performance. This evidence suggests that memorization occurs due to the fundamental nature of SFT training rather than the SFT data.

![Refer to caption](x10.png)

Figure 15: SFT experiments on GP-L with suboptimal trajectories. Similar to results in [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), SFT overfits the training data even we increase the trajectory diversity. 

### C.2 Training Pipeline

As illustrated in [Section 5](https://arxiv.org/html/2501.17161v2#S5 "5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we follow the training pipeline by RL4VLM (Zhai et al., [2024a](https://arxiv.org/html/2501.17161v2#bib.bib60 "")), where we first initialize the model with SFT, then separately scale up the compute for SFT and RL (Schulman et al., [2017](https://arxiv.org/html/2501.17161v2#bib.bib38 "")), starting from this initialized model. For all experiments of SFT and RL in the main body, we tune all components using a shared learning rate per experiment. All training experiments are conducted on an 8 H800 machine (80GB).

### C.3 Evaluation Metric

#### Per-step accuracy.

We report the per-step accuracy for  V-IRL-VL task in [Figures 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [6](https://arxiv.org/html/2501.17161v2#S5.F6 "Figure 6 ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). An individual step is considered correct when the model’s chosen action matches the expert trajectory at that position. Note that intermediate verification steps are counted as independent samples here.

#### Success rate.

We report the success rate (%) of GP-L, GP-VL, V-IRL-L and V-IRL-VL in [Figures 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [6](https://arxiv.org/html/2501.17161v2#S5.F6 "Figure 6 ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). In the GeneralPoints task, success is defined as succeeding at least once during the inference time verification. In the V-IRL task, a sample is recorded as success when the model takes correct action at each movable point on the route.

#### Computation estimation.

We estimate the FLOPs for training X𝑋Xitalic\_X following the similar manner of  (Snell et al., [2024](https://arxiv.org/html/2501.17161v2#bib.bib40 ""); Hoffmann et al., [2023](https://arxiv.org/html/2501.17161v2#bib.bib21 "")), where Xt⁢r⁢a⁢i⁢n\=6⁢N⁢Dt⁢r⁢a⁢i⁢nsubscript𝑋𝑡𝑟𝑎𝑖𝑛6𝑁subscript𝐷𝑡𝑟𝑎𝑖𝑛X\_{train}=6ND\_{train}italic\_X start\_POSTSUBSCRIPT italic\_t italic\_r italic\_a italic\_i italic\_n end\_POSTSUBSCRIPT = 6 italic\_N italic\_D start\_POSTSUBSCRIPT italic\_t italic\_r italic\_a italic\_i italic\_n end\_POSTSUBSCRIPT and Xi⁢n⁢f⁢e⁢r⁢e⁢n⁢c⁢e\=2⁢N⁢Di⁢n⁢f⁢e⁢r⁢e⁢n⁢c⁢esubscript𝑋𝑖𝑛𝑓𝑒𝑟𝑒𝑛𝑐𝑒2𝑁subscript𝐷𝑖𝑛𝑓𝑒𝑟𝑒𝑛𝑐𝑒X\_{inference}=2ND\_{inference}italic\_X start\_POSTSUBSCRIPT italic\_i italic\_n italic\_f italic\_e italic\_r italic\_e italic\_n italic\_c italic\_e end\_POSTSUBSCRIPT = 2 italic\_N italic\_D start\_POSTSUBSCRIPT italic\_i italic\_n italic\_f italic\_e italic\_r italic\_e italic\_n italic\_c italic\_e end\_POSTSUBSCRIPT. Here, N𝑁Nitalic\_N represents the model parameters and Dt⁢r⁢a⁢i⁢nsubscript𝐷𝑡𝑟𝑎𝑖𝑛D\_{train}italic\_D start\_POSTSUBSCRIPT italic\_t italic\_r italic\_a italic\_i italic\_n end\_POSTSUBSCRIPT represents the number of tokens during training. Suppose our SFT and RL experients starts from a checkpoint trained on Di⁢n⁢i⁢tsubscript𝐷𝑖𝑛𝑖𝑡D\_{init}italic\_D start\_POSTSUBSCRIPT italic\_i italic\_n italic\_i italic\_t end\_POSTSUBSCRIPT tokens, we can estimate the training computation of SFT and RL via the following equations:

XS⁢F⁢Tsubscript𝑋𝑆𝐹𝑇\\displaystyle X\_{SFT}italic\_X start\_POSTSUBSCRIPT italic\_S italic\_F italic\_T end\_POSTSUBSCRIPT

\=6⁢N⁢(Di⁢n⁢i⁢t+DS⁢F⁢T)absent6𝑁subscript𝐷𝑖𝑛𝑖𝑡subscript𝐷𝑆𝐹𝑇\\displaystyle=6N(D\_{init}+D\_{SFT})\= 6 italic\_N ( italic\_D start\_POSTSUBSCRIPT italic\_i italic\_n italic\_i italic\_t end\_POSTSUBSCRIPT + italic\_D start\_POSTSUBSCRIPT italic\_S italic\_F italic\_T end\_POSTSUBSCRIPT )

XR⁢Lsubscript𝑋𝑅𝐿\\displaystyle X\_{RL}italic\_X start\_POSTSUBSCRIPT italic\_R italic\_L end\_POSTSUBSCRIPT

\=6⁢N⁢(Di⁢n⁢i⁢t+DR⁢L)+2⁢N⁢Db⁢u⁢f⁢f⁢e⁢rabsent6𝑁subscript𝐷𝑖𝑛𝑖𝑡subscript𝐷𝑅𝐿2𝑁subscript𝐷𝑏𝑢𝑓𝑓𝑒𝑟\\displaystyle=6N(D\_{init}+D\_{RL})+2ND\_{buffer}\= 6 italic\_N ( italic\_D start\_POSTSUBSCRIPT italic\_i italic\_n italic\_i italic\_t end\_POSTSUBSCRIPT + italic\_D start\_POSTSUBSCRIPT italic\_R italic\_L end\_POSTSUBSCRIPT ) + 2 italic\_N italic\_D start\_POSTSUBSCRIPT italic\_b italic\_u italic\_f italic\_f italic\_e italic\_r end\_POSTSUBSCRIPT

Note that the used on-policy RL algorithm PPO (Schulman et al., [2017](https://arxiv.org/html/2501.17161v2#bib.bib38 "")) contains iterative stages of replay buffer collection and optimization, hence requiring additional inference computation. For simplicity, we approximate the term via:

Db⁢u⁢f⁢f⁢e⁢rsubscript𝐷𝑏𝑢𝑓𝑓𝑒𝑟\\displaystyle D\_{buffer}italic\_D start\_POSTSUBSCRIPT italic\_b italic\_u italic\_f italic\_f italic\_e italic\_r end\_POSTSUBSCRIPT

≈E⁢di¯⁢do¯DR⁢L⋅DR⁢Labsent⋅𝐸¯subscript𝑑𝑖¯subscript𝑑𝑜subscript𝐷𝑅𝐿subscript𝐷𝑅𝐿\\displaystyle\\approx\\frac{E\\bar{d\_{i}}\\bar{d\_{o}}}{D\_{RL}}\\cdot D\_{RL}≈ divide start\_ARG italic\_E over¯ start\_ARG italic\_d start\_POSTSUBSCRIPT italic\_i end\_POSTSUBSCRIPT end\_ARG over¯ start\_ARG italic\_d start\_POSTSUBSCRIPT italic\_o end\_POSTSUBSCRIPT end\_ARG end\_ARG start\_ARG italic\_D start\_POSTSUBSCRIPT italic\_R italic\_L end\_POSTSUBSCRIPT end\_ARG ⋅ italic\_D start\_POSTSUBSCRIPT italic\_R italic\_L end\_POSTSUBSCRIPT

\=λ⁢DR⁢Labsent𝜆subscript𝐷𝑅𝐿\\displaystyle=\\lambda D\_{RL}\= italic\_λ italic\_D start\_POSTSUBSCRIPT italic\_R italic\_L end\_POSTSUBSCRIPT

where E∈ℕ𝐸ℕE\\in\\mathbb{N}italic\_E ∈ blackboard\_N denotes the number of auto-regressive generation processes, di¯,do¯¯subscript𝑑𝑖¯subscript𝑑𝑜\\bar{d\_{i}},\\bar{d\_{o}}over¯ start\_ARG italic\_d start\_POSTSUBSCRIPT italic\_i end\_POSTSUBSCRIPT end\_ARG , over¯ start\_ARG italic\_d start\_POSTSUBSCRIPT italic\_o end\_POSTSUBSCRIPT end\_ARG denote average input tokens and output tokens. We estimate the λ𝜆\\lambdaitalic\_λ for GeneralPoints and V-IRL as 6666 and 5.15.15.15.1 respectively after calculation.

![Refer to caption](x11.png)

Figure 16: Ablation studies on GeneralPoints-VL SFT. We ablate the learning rate and report the in-distribution episode success rate (%percent\\%%) of all experiments. None of the experiments shows an increasing trend beyond 30%percent3030\\%30 % success rate.

#### Line smoothing and error bar.

All line plots in our paper adopt Savitzky–Golay filter with polynomial order 3 as smoothing function. We assume each evaluated data point follows a binomial distribution and approximate the standard error using P⁢(1−P)N𝑃1𝑃𝑁\\sqrt{\\frac{P(1-P)}{N}}square-root start\_ARG divide start\_ARG italic\_P ( 1 - italic\_P ) end\_ARG start\_ARG italic\_N end\_ARG end\_ARG, where P𝑃Pitalic\_P is the demical success rate and N𝑁Nitalic\_N is the number of samples.

## Appendix D Additional Experimental Results

In this section, we provide additional experimental results that are not covered in the main body.

### D.1 Ablation Studies on GP-VL

As mentioned in [Section 6](https://arxiv.org/html/2501.17161v2#S6 "6 Conclusion, Discussion, and Limitations ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we observe an abnormal phenomenon that SFT fails to achieve comparable in-distribution performance with RL (see [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") subplot row 1 column 3). To further explore this, we conduct ablation studies over different hyperparameter choices.

#### SFT.

We ablate the hyperparameter choices under the same task setting of GP-VL in [Section 5.1](https://arxiv.org/html/2501.17161v2#S5.SS1 "5.1 Generalization across Rules ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). For experiments fine-tuning all parameters, we search learning rates from {1×10−4,1×10−4,1×10−5,1×10−6,5×10−7,1×10−7}1superscript1041superscript1041superscript1051superscript1065superscript1071superscript107\\{1\\times 10^{-4},1\\times 10^{-4},1\\times 10^{-5},1\\times 10^{-6},5\\times 10^{% -7},1\\times 10^{-7}\\}{ 1 × 10 start\_POSTSUPERSCRIPT - 4 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 4 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 5 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 6 end\_POSTSUPERSCRIPT , 5 × 10 start\_POSTSUPERSCRIPT - 7 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 7 end\_POSTSUPERSCRIPT }. Freezing the vision encoder, we search learning rates {1×10−6,1×10−7}1superscript1061superscript107\\{1\\times 10^{-6},1\\times 10^{-7}\\}{ 1 × 10 start\_POSTSUPERSCRIPT - 6 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 7 end\_POSTSUPERSCRIPT }. Freezing vision encoder and adapter, we search learning rates {1×10−6,5×10−7,1×10−7}1superscript1065superscript1071superscript107\\{1\\times 10^{-6},5\\times 10^{-7},1\\times 10^{-7}\\}{ 1 × 10 start\_POSTSUPERSCRIPT - 6 end\_POSTSUPERSCRIPT , 5 × 10 start\_POSTSUPERSCRIPT - 7 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 7 end\_POSTSUPERSCRIPT }. We provide the in-distribution success rate curve in [Figure 16](https://arxiv.org/html/2501.17161v2#A3.F16 "In Computation estimation. ‣ C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

#### RL.

Finding suitable hyperparameters for RL experiments requires minimal effort. We conduct a search over learning rates 2×10−6,1×10−62superscript1061superscript106{2\\times 10^{-6},1\\times 10^{-6}}2 × 10 start\_POSTSUPERSCRIPT - 6 end\_POSTSUPERSCRIPT , 1 × 10 start\_POSTSUPERSCRIPT - 6 end\_POSTSUPERSCRIPT, with the in-distribution success rate curves shown in [Figure 17](https://arxiv.org/html/2501.17161v2#A4.F17 "In RL. ‣ D.1 Ablation Studies on GP-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). All parameters are tunable in our RL experiments.

![Refer to caption](x12.png)

Figure 17: Ablation studies on GeneralPoints-VL RL. Echoing [Figure 16](https://arxiv.org/html/2501.17161v2#A3.F16 "In Computation estimation. ‣ C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we ablate the learning rate and rreport the in-distribution episode success rate (%percent\\%%) of the two experiments. All components are tunable here.

### D.2 More results on V-IRL-VL

Echoing per-step accuracy results in [Figure 5](https://arxiv.org/html/2501.17161v2#S5.F5 "In 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we report the overall success rate of V-IRL-VL in [Figure 19](https://arxiv.org/html/2501.17161v2#A4.F19 "In D.2 More results on V-IRL-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). Due to the task’s complexity, both training methods achieve overall success rates no higher than 1%percent11\\%1 %. For V-IRL, the overall success rate is a significantly more demanding metric since it aggregates per-step errors. For example, a random policy achieving 10%percent1010\\%10 % per-step accuracy would achieve achieve only approximately 10−8%percentsuperscript10810^{-8}\\%10 start\_POSTSUPERSCRIPT - 8 end\_POSTSUPERSCRIPT % success rate on enough routes averaging 10 steps in length.

![Refer to caption](x13.png)

Figure 18: Overall success rate (%) - GFLOPs for V-IRL-VL under rule variants. Due to the nature of the task requiring aggregating a trajectory of correct actions, neither training method achieves reasonable out-of-distribution performance. 

![Refer to caption](x14.png)

Figure 19: Out-of-distribution per-step accuracy (%) - GFLOPs for V-IRL-VL under rule variants with overfitted initial checkpoint. Evaluation metric details can be found in [Section C.3](https://arxiv.org/html/2501.17161v2#A3.SS3 "C.3 Evaluation Metric ‣ Appendix C Experimental Setup ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

### D.3 Failure Cases

In this section, we present 2 failure cases in our experiments as mentioned in [Sections 5.4](https://arxiv.org/html/2501.17161v2#S5.SS4 "5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training") and [6](https://arxiv.org/html/2501.17161v2#S6 "6 Conclusion, Discussion, and Limitations ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training").

#### Without SFT, RL fails.

In [Figure 9](https://arxiv.org/html/2501.17161v2#S5.F9 "In 5.4 The Role of SFT for RL Training ‣ 5 Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), we present the training dynamics of failed RL experiments without SFT initialization. We additionally provide output examples of these experiments in [Figure 20](https://arxiv.org/html/2501.17161v2#A4.F20 "In RL cannot save overfitted checkpoints. ‣ D.3 Failure Cases ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), where the model tends to generate unstructured response and fail.

#### RL cannot save overfitted checkpoints.

As shown in [Figure 19](https://arxiv.org/html/2501.17161v2#A4.F19 "In D.2 More results on V-IRL-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), RL cannot recover the out-of-distribution performance when initialized from a extremely overfitted checkpoint that has an initial per-step accuracy of less than 1%percent11\\%1 %. We additionally provide an output example in [Figure 19](https://arxiv.org/html/2501.17161v2#A4.F19 "In D.2 More results on V-IRL-VL ‣ Appendix D Additional Experimental Results ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"), where the model fails to adjust to the new rule.

Figure 20: Example model outputs without SFT initialization. We record model responses using prompts similar to the one shown in [Figure 11](https://arxiv.org/html/2501.17161v2#A1.F11 "In A.2 Detailed Examples on the Transition Dynamics ‣ Appendix A Details on the General Points Environment ‣ SFT Memorizes, RL Generalizes: A Comparative Study of Foundationa Model Post-training"). The results demonstrate that Llama-3.2-Vision-11B fails to follow instructions properly. We omit the long response which tries to solve the puzzle via code but fails to finish within finite context length.

Figure 21: Failed example of V-IRL transition due to overfitting. This phenomenon happens more frequently during scaling up supervised fine-tuning.