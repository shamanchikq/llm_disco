# llm_disco_test1

There is a problem with LLMs – advanced models with big parameter count need a powerful hardware to run, so they aren’t very portable. There is a demand for locally-run LLMs to fine-tune them, tinker, and keep your information private. Our phones cant run event the basic ones with 4B or 16B parameters, because they need a lot of VRAM and GPU power. That is a problem I’ll try to solve during this project. My goal is to develop an app that will connect to Ollama (app that runs LLMs locally on your PC) and let you chat with your favourite LLM that runs locally on your PC, which will act as a server. This way the user will have a powerful private LLM right in his pocket, and doesn’t need to worry about draining his phones battery or performance.

I still need to do a lot in terms of app development. This not only includes the UI, but communicating with Ollama’s API.
Speaking about it, I need to develop a server program that will run on a PC with Ollama installed and handle API calls.
I also want to get some external opinion from my friends about the app and further polish it after I have a first fully working prototype.
Probably I will come up with a couple new functions like attaching media, altering the context window, temperature and topK from the app.
