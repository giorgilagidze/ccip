predeploy: ## Simulate a protocol deployment
	@echo "Simulating the deployment"
	forge script CreateRepo \
		--rpc-url $(RPC_URL)

deploy:
	forge script CreateRepo \
		--rpc-url $(RPC_URL)