FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Note the -u flag for unbuffered output, which fixed our logging issue
CMD ["python", "-u", "main.py"]