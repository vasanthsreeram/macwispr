# Custom GRPO reward for the polish task, loaded via --reward-functions-file.
# Signature per mlx_lm_lora.trainer.grpo_reward_functions: f(prompts, completions, answer, types=None)
from mlx_lm_lora.trainer.grpo_reward_functions import register_reward_function

from polish_verifier import verify


def _raw_from_prompt(prompt: str) -> str:
    # prompt is "### Input:\n<raw>\n\n### Output:\n"
    if "### Input:" in prompt:
        body = prompt.split("### Input:", 1)[1]
        return body.split("### Output:", 1)[0].strip()
    return prompt.strip()


@register_reward_function("polish_reward")
def polish_reward(prompts, completions, answer, types=None):
    scores = []
    for i, completion in enumerate(completions):
        raw = _raw_from_prompt(prompts[i] if i < len(prompts) else prompts[0])
        tag_str = (types[i] if types and i < len(types) else "") or ""
        tags = [t for t in tag_str.split(",") if t]
        out = completion.split("### Input:")[0].strip()
        try:
            scores.append(float(verify(raw, out, tags).score))
        except Exception:
            scores.append(0.0)
    return scores
