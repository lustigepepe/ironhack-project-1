# Key Points About the Dockerfiles:

vote (Python): The provided Dockerfile installs dependencies via pip, sets up the Python environment, and uses gunicorn for a production-ready server. There’s also a dev stage allowing you to run the application with file watching.

result (Node.js): The Dockerfile installs dependencies, uses nodemon for development, and runs the Node.js server on port 80.

worker (.NET): The Dockerfile uses multi-stage builds to restore, build, and publish a .NET 7 app, then runs it in the runtime-only container.

# two

Application Distribution

Instance A (Application Tier - Frontend): An EC2 instance launched in any AZ that runs the Vote (Python/Flask) and Result (Node.js/Express) services.

Instance B (Data/Backend Services): Runs Redis and the Worker (.NET) in a private subnet (single AZ or multi-AZ for high availability).

Instance C (Database Tier): Runs PostgreSQL in its own private subnet, optionally with a read-replica in a second AZ.

## Pull your images from DockerHub on the EC2 instances.
