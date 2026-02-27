require "../../spec_helper"

module Ameba::LSP
  describe Ameba::LSP::Protocol::ErrorCode do
    it "matches JSON-RPC and LSP numeric values" do
      Ameba::LSP::Protocol::ErrorCode::ParseError.value.should eq(-32700)
      Ameba::LSP::Protocol::ErrorCode::InvalidRequest.value.should eq(-32600)
      Ameba::LSP::Protocol::ErrorCode::MethodNotFound.value.should eq(-32601)
      Ameba::LSP::Protocol::ErrorCode::InvalidParams.value.should eq(-32602)
      Ameba::LSP::Protocol::ErrorCode::InternalError.value.should eq(-32603)
      Ameba::LSP::Protocol::ErrorCode::RequestCancelled.value.should eq(-32800)
    end
  end

  describe Ameba::LSP::Protocol::PositionEncoding do
    it "maps protocol strings to enum values" do
      Ameba::LSP::Protocol::PositionEncoding.from_protocol?("utf-8").should eq(Ameba::LSP::Protocol::PositionEncoding::UTF8)
      Ameba::LSP::Protocol::PositionEncoding.from_protocol?("utf-16").should eq(Ameba::LSP::Protocol::PositionEncoding::UTF16)
      Ameba::LSP::Protocol::PositionEncoding.from_protocol?("utf-32").should eq(Ameba::LSP::Protocol::PositionEncoding::UTF32)
    end

    it "returns nil for unsupported protocol strings" do
      Ameba::LSP::Protocol::PositionEncoding.from_protocol?("utf-7").should be_nil
    end

    it "maps enum values back to protocol strings" do
      Ameba::LSP::Protocol::PositionEncoding::UTF8.to_protocol.should eq("utf-8")
      Ameba::LSP::Protocol::PositionEncoding::UTF16.to_protocol.should eq("utf-16")
      Ameba::LSP::Protocol::PositionEncoding::UTF32.to_protocol.should eq("utf-32")
    end
  end
end
