#!/usr/bin/env python3
"""
Stable Diffusion / FLUX CLI for Godot integration
Generates images using local models via diffusers library

Usage:
    python3 sd_cli.py --prompt "medieval shop, top-down view" --output output.png
    python3 sd_cli.py --prompt "tavern building" --width 512 --height 512 --seed 42
    python3 sd_cli.py --prompt "fantasy tree" --flux  # Use FLUX model
"""

import argparse
import sys
import os

def main():
    parser = argparse.ArgumentParser(description='Generate images with Stable Diffusion/FLUX')
    parser.add_argument('--prompt', required=True, help='Text prompt for generation')
    parser.add_argument('--negative', default='', help='Negative prompt')
    parser.add_argument('--width', type=int, default=512, help='Image width')
    parser.add_argument('--height', type=int, default=512, help='Image height')
    parser.add_argument('--output', required=True, help='Output file path')
    parser.add_argument('--seed', type=int, default=-1, help='Random seed (-1 for random)')
    parser.add_argument('--model', default='', help='Path to model weights')
    parser.add_argument('--flux', action='store_true', help='Use FLUX model instead of SD')
    parser.add_argument('--steps', type=int, default=20, help='Number of inference steps')
    parser.add_argument('--guidance', type=float, default=7.5, help='Guidance scale')

    args = parser.parse_args()

    try:
        import torch
        from diffusers import StableDiffusionPipeline, FluxPipeline
        from diffusers import DPMSolverMultistepScheduler
    except ImportError as e:
        print(f"Error: Required packages not installed. Run: pip install torch diffusers transformers accelerate")
        print(f"Details: {e}")
        sys.exit(1)

    # Determine device
    if torch.cuda.is_available():
        device = "cuda"
        dtype = torch.float16
    elif torch.backends.mps.is_available():
        device = "mps"
        dtype = torch.float16
    else:
        device = "cpu"
        dtype = torch.float32
        print("Warning: Running on CPU, generation will be slow")

    # Set seed
    if args.seed >= 0:
        generator = torch.Generator(device=device).manual_seed(args.seed)
    else:
        generator = None

    try:
        if args.flux:
            # Load FLUX model
            model_id = args.model if args.model else "black-forest-labs/FLUX.1-schnell"
            print(f"Loading FLUX model: {model_id}")
            pipe = FluxPipeline.from_pretrained(
                model_id,
                torch_dtype=dtype
            )
        else:
            # Load Stable Diffusion model
            model_id = args.model if args.model else "runwayml/stable-diffusion-v1-5"
            print(f"Loading SD model: {model_id}")
            pipe = StableDiffusionPipeline.from_pretrained(
                model_id,
                torch_dtype=dtype,
                safety_checker=None  # Disable for game assets
            )
            # Use faster scheduler
            pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config)

        pipe = pipe.to(device)

        # Enable memory optimizations
        if device == "cuda":
            pipe.enable_attention_slicing()
            try:
                pipe.enable_xformers_memory_efficient_attention()
            except:
                pass  # xformers not available

        print(f"Generating: {args.prompt}")

        # Generate image
        if args.flux:
            result = pipe(
                args.prompt,
                height=args.height,
                width=args.width,
                num_inference_steps=args.steps,
                generator=generator,
            )
        else:
            result = pipe(
                args.prompt,
                negative_prompt=args.negative if args.negative else None,
                height=args.height,
                width=args.width,
                num_inference_steps=args.steps,
                guidance_scale=args.guidance,
                generator=generator,
            )

        image = result.images[0]

        # Ensure output directory exists
        os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)

        # Save image
        image.save(args.output)
        print(f"Saved: {args.output}")

    except Exception as e:
        print(f"Generation failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
