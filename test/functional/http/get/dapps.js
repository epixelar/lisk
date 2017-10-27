'use strict';

var node = require('../../../node.js');

var sendTransactionPromise = require('../../../common/apiHelpers').sendTransactionPromise;
var creditAccountPromise = require('../../../common/apiHelpers').creditAccountPromise;
var getDappPromise = require('../../../common/apiHelpers').getDappPromise;
var getDappsPromise = require('../../../common/apiHelpers').getDappsPromise;
var getDappsCategoriesPromise = require('../../../common/apiHelpers').getDappsCategoriesPromise;
var waitForConfirmations = require('../../../common/apiHelpers').waitForConfirmations;

describe('GET /api/dapps', function () {	
	
	var transaction;
	var transactionsToWaitFor = [];

	var account = node.randomAccount();
	var dapp1 = node.randomApplication();
	dapp1.category = 1;
	var dapp2 = node.randomApplication();
	dapp2.category = 2;
	
	before(function () {
		var promises = [];

		return creditAccountPromise(account.address, 1000 * node.normalizer)
			.then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').that.is.not.empty;
				
				transactionsToWaitFor.push(res.transactionId);
				return waitForConfirmations(transactionsToWaitFor);
			})
			.then(function (res) {
				transaction = node.lisk.dapp.createDapp(account.password, null, dapp1);
				
				return sendTransactionPromise(transaction);
			})
			.then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').to.equal(transaction.id);
				transactionsToWaitFor = [];
				dapp1.id = transaction.id;
				transactionsToWaitFor.push(res.transactionId);
			})
			.then(function (res) {
				transaction = node.lisk.dapp.createDapp(account.password, null, dapp2);

				return sendTransactionPromise(transaction);
			})
			.then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('transactionId').to.equal(transaction.id);	
				transactionsToWaitFor = [];
				dapp2.id = transaction.id;
				transactionsToWaitFor.push(res.transactionId);
							
				return waitForConfirmations(transactionsToWaitFor);
			});
	});

	describe('/get?id=', function () {

		it('using no id should fail', function () {
			return getDappPromise('').then(function (res) {
				node.expect(res).to.have.property('success').to.be.not.ok;
				node.expect(res).to.have.property('error').that.is.equal('String is too short (0 chars), minimum 1: #/id');
			});
		});

		it('using non-numeric id should fail', function () {
			var dappId = 'ABCDEFGHIJKLMNOPQRST';

			return getDappPromise(dappId).then(function (res) {
				node.expect(res).to.have.property('success').to.be.not.ok;
				node.expect(res).to.have.property('error').that.is.equal('Object didn\'t pass validation for format id: ABCDEFGHIJKLMNOPQRST: #/id');
			});
		});

		it('using id with length > 20 should fail', function () {
			return getDappPromise('012345678901234567890').then(function (res) {
				node.expect(res).to.have.property('success').to.not.be.ok;
				node.expect(res).to.have.property('error').that.is.equal('String is too long (21 chars), maximum 20: #/id');
			});
		});

		it('using unknown id should fail', function () {
			var dappId = '8713095156789756398';

			return getDappPromise(dappId).then(function (res) {
				node.expect(res).to.have.property('success').to.be.not.ok;
				node.expect(res).to.have.property('error').that.is.equal('Application not found');
			});
		});

		it('using known id should be ok', function () {
			return getDappPromise(dapp1.id).then(function (res) {
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('dapp').that.is.an('object');
				node.expect(res.dapp).to.have.property('name').that.is.equal(dapp1.name);
			});
		});
	});

	describe('?', function () {

		describe('type', function () {

			it('using no integer should fail', function () {
				var params = [
					'type='
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Expected type integer but found type string: #/type');
				});
			});

			it('using non-numeric should fail', function () {
				var params = [
					'type=' + 'A'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Expected type integer but found type string: #/type');
				});
			});

			it('using -1 should fail', function () {
				var params = [
					'type=' + '-1'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Value -1 is less than minimum 0: #/type');
				});
			});

			it('using 0 should be ok', function () {
				var params = [
					'type=' + '0'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
				});
			});

			it('using 1 should be ok', function () {
				var params = [
					'type=' + '1'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
				});
			});
		});

		describe('name=', function () {

			it('using string with length < 1 should fail', function () {
				var params = [
					'name='
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('String is too short (0 chars), minimum 1: #/name');
				});
			});

			it('using string with length > 32 should fail', function () {
				var params = [
					'name=' + 'ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFG'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('String is too long (33 chars), maximum 32: #/name');
				});
			});

			it('using string == "Unknown" should be ok', function () {
				var params = [
					'name=' + 'Unknown'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success');
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(0);
				});
			});

			it('uusing registered dapp1 name should be ok', function () {
				var params = [
					'name=' + dapp1.name
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success');
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(1);
					node.expect(res.dapps[0].name).to.equal(dapp1.name);

				});
			});

			it('using registered dapp2 name should be ok', function () {
				var params = [
					'name=' + dapp2.name
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success');
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(1);
					node.expect(res.dapps[0].name).to.equal(dapp2.name);
				});
			});
		});

		describe('category=', function () {

			it('using integer should fail', function () {
				var params = [
					'category=' + 0
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Expected type string but found type integer: #/category');
				});
			});

			it('using registered category from dapp1 should be ok', function () {
				var params = [
					'category=' + 'Entertainment'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success');
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf.at.least(1);
					node.expect(res.dapps[0].category).to.equal(node.dappCategories['Entertainment']);
				});
			});

			it('using registered category from dapp2 should be ok', function () {
				var params = [
					'category=' + 'Finance'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success');
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf.at.least(1);
					node.expect(res.dapps[0].category).to.equal(node.dappCategories['Finance']);
				});
			});

			it('using string "Unknown"', function () {
				var params = [
					'category=' + 'Unknown'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Invalid application category');
				});
			});
		});

		describe('link=', function () {

			it('using integer should fail', function () {
				var params = [
					'link=' + 0
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Expected type string but found type integer: #/link');
				});
			});

			it('using string length < 1 should fail', function () {
				var params = [
					'link='
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('String is too short (0 chars), minimum 1: #/link');
				});
			});

			it('using string length > 2000 should fail', function () {
				var params = [
					'link=' + 'https://github.com/MaxKK/xxxxxx/archive/master.zip'.repeat(40) + '1'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('String is too long (2001 chars), maximum 2000: #/link');
				});
			});

			it('using registered string should be ok', function () {
				var params = [
					'link=' + dapp1.link
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(1);
					node.expect(res.dapps[0].link).to.equal(dapp1.link);
				});
			});

			it('using unregistered string should be ok', function () {
				var params = [
					'link=' + 'https://github.com/MaxKK/xxxxxx/archive/master.zip'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(0);
				});
			});
		});

		describe('limit=', function () {

			it('using 0 should fail', function () {
				var params = [
					'limit=' + 0
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Value 0 is less than minimum 1: #/limit');
				});
			});

			it('using integer > 100 should fail', function () {
				var params = [
					'limit=' + 101
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Value 101 is greater than maximum 100: #/limit');
				});
			});

			it('using 1 should be ok', function () {
				var params = [
					'limit=' + 1
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
					node.expect(res.dapps).to.have.length.at.most(1);
				});
			});

			it('using 100 should be ok', function () {
				var params = [
					'limit=' + 100
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
					node.expect(res.dapps).to.have.length.at.most(100);
				});
			});
		});

		describe('limit=1&', function () {

			it('using offset < 0 should fail', function () {
				var params = [
					'limit=' + 1,
					'offset=' + '-1'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.not.ok;
					node.expect(res).to.have.property('error').that.is.equal('Value -1 is less than minimum 0: #/offset');
				});
			});

			it('using offset 0 should be ok', function () {
				var params = [
					'limit=' + 1,
					'offset=' + 0
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(1);
				});
			});

			it('using offset 1 should be ok', function () {
				var params = [
					'limit=' + 1,
					'offset=' + 1
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array').and.has.lengthOf(1);
				});
			});
		});

		describe('orderBy=', function () {

			it('using "category:asc" should be ok', function () {
				var params = [
					'category:asc'
				];
				
				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
					node.expect(res.dapps[0].category).to.be.at.least(res.dapps[1].category);
				});
			});

			it('using "category:desc" should be ok', function () {
				var params = [
					'category:desc'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
					node.expect(res.dapps[0].category).to.be.at.least(res.dapps[1].category);
				});
			});

			it('using "category:unknown" should be ok', function () {
				var params = [
					'category:unknown'
				];
								
				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
					node.expect(res.dapps[0].category).to.be.at.least(res.dapps[1].category);
				});
			});

			it('using "unknown:unknown" should be ok', function () {
				var params = [
					'unknown:unknown'
				];

				return getDappsPromise(params).then(function (res) {
					node.expect(res).to.have.property('success').to.be.ok;
					node.expect(res).to.have.property('dapps').that.is.an('array');
					node.expect(res.dapps[0].category).to.be.at.least(res.dapps[1].category);
				});
			});
		});
	});

	describe('/categories', function () {

		it('should be ok', function () {
			var params = [];
			
			return getDappsCategoriesPromise(params).then(function (res){
				node.expect(res).to.have.property('success').to.be.ok;
				node.expect(res).to.have.property('categories').that.is.an('object');
				for (var i in node.dappCategories) {
					node.expect(res.categories[i]).to.equal(node.dappCategories[i]);
				}
			});
		});
	});
});