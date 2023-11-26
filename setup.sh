rm -rf .venv-1
python -m venv .venv-1
. .venv-1/bin/activate
pip install -r requirements.txt
deactivate

rm -rf .venv-2
python -m venv .venv-2
. .venv-2/bin/activate
pip install -r requirements.txt
pip install -e .
deactivate
